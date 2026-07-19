#include "llvm/Config/llvm-config.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/ModRef.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/Local.h"

#include <cassert>
#include <cstdlib>
#include <optional>
#include <utility>
#include <vector>

namespace aco {

class ThreeWayCompareSwitchPass
    : public llvm::PassInfoMixin<ThreeWayCompareSwitchPass> {
  static void replaceIncomingBlock(llvm::BasicBlock &Block,
                                   llvm::BasicBlock &Old,
                                   llvm::BasicBlock &Replacement) {
    for (llvm::PHINode &Phi : Block.phis()) {
      int Index = Phi.getBasicBlockIndex(&Old);
      assert(Index >= 0 && "switch successor PHI is missing its predecessor");
      Phi.setIncomingBlock(Index, &Replacement);
    }
  }

  static bool lower(llvm::SwitchInst &Switch) {
    auto *Compare = llvm::dyn_cast<llvm::IntrinsicInst>(Switch.getCondition());
    if (!Compare || Compare->getIntrinsicID() != llvm::Intrinsic::scmp ||
        Compare->getParent() != Switch.getParent() || !Compare->hasOneUse() ||
        !Compare->getType()->isIntegerTy(8) ||
        !Compare->getArgOperand(0)->getType()->isIntegerTy(64) ||
        Compare->getArgOperand(1)->getType() !=
            Compare->getArgOperand(0)->getType() ||
        Switch.getNumCases() != 3)
      return false;

    llvm::BasicBlock *Less = nullptr;
    llvm::BasicBlock *Equal = nullptr;
    llvm::BasicBlock *Greater = nullptr;
    for (auto Case : Switch.cases()) {
      const llvm::APInt &Value = Case.getCaseValue()->getValue();
      if (Value.isAllOnes())
        Less = Case.getCaseSuccessor();
      else if (Value.isZero())
        Equal = Case.getCaseSuccessor();
      else if (Value.isOne())
        Greater = Case.getCaseSuccessor();
      else
        return false;
    }

    llvm::BasicBlock *Invalid = Switch.getDefaultDest();
    if (!Less || !Equal || !Greater || Less == Equal || Less == Greater ||
        Equal == Greater || Invalid == Less || Invalid == Equal ||
        Invalid == Greater ||
        !llvm::isa<llvm::UnreachableInst>(Invalid->getTerminator()))
      return false;

    llvm::BasicBlock *Source = Switch.getParent();
    llvm::Function *Function = Source->getParent();
    llvm::BasicBlock *NonLess = llvm::BasicBlock::Create(
        Function->getContext(), "aco.scmp.nonless", Function, Equal);

    // The proved candidate maps scmp's three possible results to these same
    // signed predicates. The default is unreachable because scmp returns only
    // -1, 0, or 1; retaining that requirement keeps the CFG rewrite local.
    Invalid->removePredecessor(Source);
    replaceIncomingBlock(*Equal, *Source, *NonLess);
    replaceIncomingBlock(*Greater, *Source, *NonLess);

    llvm::Value *Left = Compare->getArgOperand(0);
    llvm::Value *Right = Compare->getArgOperand(1);
    llvm::DebugLoc Location = Switch.getDebugLoc();
    Switch.eraseFromParent();

    llvm::IRBuilder<> SourceBuilder(Source);
    SourceBuilder.SetCurrentDebugLocation(Location);
    // scmp consumes each operand once, but the staged replacement compares
    // them in two blocks. Freeze once so an undef-producing SSA value cannot
    // choose a different value in the less-than and equality comparisons.
    llvm::Value *FrozenLeft = SourceBuilder.CreateFreeze(Left, "aco.left");
    llvm::Value *FrozenRight = SourceBuilder.CreateFreeze(Right, "aco.right");
    llvm::Value *IsLess =
        SourceBuilder.CreateICmpSLT(FrozenLeft, FrozenRight, "aco.less");
    SourceBuilder.CreateCondBr(IsLess, Less, NonLess);

    llvm::IRBuilder<> NonLessBuilder(NonLess);
    NonLessBuilder.SetCurrentDebugLocation(Location);
    llvm::Value *IsEqual = NonLessBuilder.CreateICmpEQ(
        FrozenLeft, FrozenRight, "aco.equal");
    NonLessBuilder.CreateCondBr(IsEqual, Equal, Greater);

    Compare->eraseFromParent();
    return true;
  }

public:
  llvm::PreservedAnalyses run(llvm::Function &Function,
                              llvm::FunctionAnalysisManager &) {
    unsigned Rewrites = 0;
    for (llvm::BasicBlock &Block : Function) {
      auto *Switch = llvm::dyn_cast<llvm::SwitchInst>(Block.getTerminator());
      if (Switch && lower(*Switch))
        ++Rewrites;
    }

    if (std::getenv("ACO_OPTIMIZER_TRACE") && Rewrites != 0)
      llvm::errs() << "aco-three-way-compare: transformed " << Rewrites
                   << " switch(es) in " << Function.getName() << '\n';
    return Rewrites == 0 ? llvm::PreservedAnalyses::all()
                         : llvm::PreservedAnalyses::none();
  }
};

class KeyholePass : public llvm::PassInfoMixin<KeyholePass> {
public:
  KeyholePass(bool EnableSliceComparisons, bool EnableMidpoints)
      : EnableSliceComparisons(EnableSliceComparisons),
        EnableMidpoints(EnableMidpoints) {}

  llvm::PreservedAnalyses run(llvm::Function &Function,
                              llvm::FunctionAnalysisManager &Analyses) {
    llvm::TargetLibraryInfo &LibraryInfo =
        Analyses.getResult<llvm::TargetLibraryAnalysis>(Function);
    std::vector<llvm::CallInst *> MemcmpCandidates;
    struct MidpointCandidate {
      llvm::TruncInst *Trunc;
      llvm::Value *Minimum;
      llvm::Value *Maximum;
    };
    struct SliceCompareCandidate {
      llvm::CallInst *Memcmp;
      llvm::CallInst *Ordering;
    };
    std::vector<SliceCompareCandidate> SliceCompareCandidates;
    std::vector<MidpointCandidate> MidpointCandidates;

    for (llvm::BasicBlock &Block : Function) {
      for (llvm::Instruction &Instruction : Block) {
        auto *Call = llvm::dyn_cast<llvm::CallInst>(&Instruction);
        if (EnableSliceComparisons && Call &&
            isProvenMemcmpCall(*Call, LibraryInfo)) {
          if (llvm::CallInst *Ordering = findSliceOrderingUser(*Call))
            SliceCompareCandidates.push_back({Call, Ordering});
          else
            MemcmpCandidates.push_back(Call);
        }

        auto *Trunc = llvm::dyn_cast<llvm::TruncInst>(&Instruction);
        if (EnableMidpoints && Trunc) {
          auto Operands = findOrderedMidpointOperands(*Trunc);
          if (Operands)
            MidpointCandidates.push_back(
                {Trunc, Operands->first, Operands->second});
        }
      }
    }

    for (const SliceCompareCandidate &Candidate : SliceCompareCandidates)
      expandSliceCompareFirstByte(*Candidate.Memcmp, *Candidate.Ordering);
    for (llvm::CallInst *Call : MemcmpCandidates)
      expandMemcmpFirstByte(*Call);
    for (const MidpointCandidate &Candidate : MidpointCandidates)
      narrowOrderedMidpoint(*Candidate.Trunc, *Candidate.Minimum,
                            *Candidate.Maximum, LibraryInfo);

    if (std::getenv("ACO_OPTIMIZER_TRACE") &&
        (!SliceCompareCandidates.empty() || !MemcmpCandidates.empty() ||
         !MidpointCandidates.empty()))
      llvm::errs() << "aco-keyhole: transformed "
                   << SliceCompareCandidates.size() << " slice compare(s), "
                   << MemcmpCandidates.size() << " generic memcmp call(s), and "
                   << MidpointCandidates.size()
                   << " ordered midpoint(s) in " << Function.getName() << '\n';

    return SliceCompareCandidates.empty() && MemcmpCandidates.empty() &&
                   MidpointCandidates.empty()
               ? llvm::PreservedAnalyses::all()
               : llvm::PreservedAnalyses::none();
  }

private:
  bool EnableSliceComparisons;
  bool EnableMidpoints;

  static bool hasUnsupportedCallControlContract(
      const llvm::CallInst &Call) {
    // Both memcmp and the slice-ordering intrinsic are relocated across new
    // control flow. Keep every control contract in one fail-closed policy so a
    // dataflow match cannot silently broaden the proof boundary.
    if (Call.isConvergent() || Call.isMustTailCall() ||
        Call.getTailCallKind() == llvm::CallInst::TCK_NoTail ||
        Call.getCallingConv() != llvm::CallingConv::C ||
        Call.hasOperandBundles() ||
        Call.hasFnAttr(llvm::Attribute::NoReturn) ||
        Call.hasFnAttr(llvm::Attribute::ReturnsTwice) ||
        Call.hasFnAttr(llvm::Attribute::NoDuplicate))
      return true;

    return false;
  }

  static bool hasUnsupportedMemcmpAttributeContract(
      const llvm::CallInst &Call, const llvm::Function &Callee) {
    // Keep the accepted attribute surface identical to the two tracked memcmp
    // obligations. Rust's slice comparison emits nonnull on both pointer
    // operands; the attributed obligation models exactly that shape. Every
    // other call-site return or parameter contract remains fail closed.
    if (Call.getAttributes().getRetAttrs().hasAttributes())
      return true;

    llvm::AttributeSet LeftAttributes =
        Call.getAttributes().getParamAttrs(0);
    llvm::AttributeSet RightAttributes =
        Call.getAttributes().getParamAttrs(1);
    llvm::AttributeSet LengthAttributes =
        Call.getAttributes().getParamAttrs(2);
    bool HasNoCallParameterAttributes =
        !LeftAttributes.hasAttributes() && !RightAttributes.hasAttributes() &&
        !LengthAttributes.hasAttributes();
    bool HasProvenNonnullAttributes =
        LeftAttributes.getNumAttributes() == 1 &&
        LeftAttributes.hasAttribute(llvm::Attribute::NonNull) &&
        RightAttributes.getNumAttributes() == 1 &&
        RightAttributes.hasAttribute(llvm::Attribute::NonNull) &&
        !LengthAttributes.hasAttributes();
    if (!HasNoCallParameterAttributes && !HasProvenNonnullAttributes)
      return true;

    if (Callee.getAttributes().getRetAttrs().hasAttributes())
      return true;

    for (unsigned Index = 0; Index != Call.arg_size(); ++Index) {
      llvm::AttributeSet CalleeAttributes =
          Callee.getAttributes().getParamAttrs(Index);
      unsigned SupportedCalleeAttributes =
          CalleeAttributes.hasAttribute(llvm::Attribute::Captures) ? 1 : 0;
      if (CalleeAttributes.getNumAttributes() != SupportedCalleeAttributes)
        return true;
    }
    return false;
  }

  static bool permitsProvenMemcmpReads(llvm::MemoryEffects Effects) {
    return llvm::isRefSet(
        Effects.getModRef(llvm::MemoryEffects::Location::ArgMem));
  }

  static bool isProvenMemcmpCall(
      const llvm::CallInst &Call,
      const llvm::TargetLibraryInfo &LibraryInfo) {
    // This predicate owns the complete boundary of the tracked i64/64-bit
    // Alive2 obligation. Do not make a call eligible unless both its LLVM
    // semantics and target domain are represented by that proof.
    if (Call.arg_size() != 3 ||
        Call.getType() != llvm::Type::getInt32Ty(Call.getContext()) ||
        Call.getMetadata("aco.expanded") ||
        hasUnsupportedCallControlContract(Call))
      return false;

    const llvm::Function *Callee = Call.getCalledFunction();
    if (!Callee || hasUnsupportedMemcmpAttributeContract(Call, *Callee) ||
        !permitsProvenMemcmpReads(
            Call.getAttributes().getMemoryEffects()) ||
        !permitsProvenMemcmpReads(Callee->getMemoryEffects()))
      return false;

    const llvm::DataLayout &Layout = Call.getModule()->getDataLayout();
    if (!Layout.isLittleEndian() || Layout.getPointerSizeInBits(0) != 64 ||
        !Call.getArgOperand(2)->getType()->isIntegerTy(64))
      return false;

    llvm::LibFunc LibraryFunction;
    if (!LibraryInfo.getLibFunc(Call, LibraryFunction) ||
        LibraryFunction != llvm::LibFunc_memcmp ||
        !LibraryInfo.has(LibraryFunction))
      return false;

    auto *LeftPointer =
        llvm::dyn_cast<llvm::PointerType>(Call.getArgOperand(0)->getType());
    auto *RightPointer =
        llvm::dyn_cast<llvm::PointerType>(Call.getArgOperand(1)->getType());
    return LeftPointer && RightPointer &&
           LeftPointer->getAddressSpace() == 0 &&
           RightPointer->getAddressSpace() == 0;
  }

  static llvm::CallInst *findSliceOrderingUser(llvm::CallInst &Memcmp) {
    if (!Memcmp.hasNUses(2))
      return nullptr;

    llvm::SExtInst *Extended = nullptr;
    llvm::ICmpInst *IsEqual = nullptr;
    for (llvm::User *User : Memcmp.users()) {
      if (auto *Extension = llvm::dyn_cast<llvm::SExtInst>(User))
        Extended = Extension;
      else if (auto *Compare = llvm::dyn_cast<llvm::ICmpInst>(User))
        IsEqual = Compare;
    }
    if (!Extended || !IsEqual || !Extended->getType()->isIntegerTy(64) ||
        IsEqual->getPredicate() != llvm::ICmpInst::ICMP_EQ ||
        !Extended->hasOneUse() || !IsEqual->hasOneUse())
      return nullptr;

    bool ComparesWithZero =
        (IsEqual->getOperand(0) == &Memcmp &&
         isZero(IsEqual->getOperand(1))) ||
        (IsEqual->getOperand(1) == &Memcmp &&
         isZero(IsEqual->getOperand(0)));
    auto *Select = llvm::dyn_cast<llvm::SelectInst>(*IsEqual->user_begin());
    if (!ComparesWithZero || !Select || Select->getCondition() != IsEqual ||
        Select->getFalseValue() != Extended || !Select->hasOneUse())
      return nullptr;

    auto *LengthDifference =
        llvm::dyn_cast<llvm::BinaryOperator>(Select->getTrueValue());
    auto *Ordering = llvm::dyn_cast<llvm::CallInst>(*Select->user_begin());
    llvm::Function *OrderingFunction = Ordering ? Ordering->getCalledFunction()
                                                : nullptr;
    if (!LengthDifference ||
        LengthDifference->getOpcode() != llvm::Instruction::Sub ||
        !LengthDifference->hasOneUse() || !Ordering || !OrderingFunction ||
        !OrderingFunction->getName().starts_with("llvm.scmp.i8.") ||
        Ordering->arg_size() != 2 || Ordering->getArgOperand(0) != Select ||
        !isZero(Ordering->getArgOperand(1)) ||
        !Ordering->getType()->isIntegerTy(8) ||
        hasUnsupportedCallControlContract(*Ordering))
      return nullptr;

    llvm::BasicBlock *Block = Memcmp.getParent();
    if (Extended->getParent() != Block || IsEqual->getParent() != Block ||
        LengthDifference->getParent() != Block || Select->getParent() != Block ||
        Ordering->getParent() != Block || !Memcmp.comesBefore(Ordering))
      return nullptr;

    // Unrelated instructions in this range are sunk to the shared join by the
    // rewrite. Keep every matched input available before the branch so that
    // sinking cannot introduce a dependency cycle.
    for (llvm::Value *Operand : LengthDifference->operands()) {
      auto *OperandInstruction = llvm::dyn_cast<llvm::Instruction>(Operand);
      if (OperandInstruction && OperandInstruction->getParent() == Block &&
          (OperandInstruction == &Memcmp ||
           Memcmp.comesBefore(OperandInstruction)))
        return nullptr;
    }
    return Ordering;
  }

  static std::optional<std::pair<llvm::Value *, llvm::Value *>>
  findOrderedMidpointOperands(const llvm::TruncInst &Trunc) {
    if (!Trunc.getSrcTy()->isIntegerTy(128) ||
        !Trunc.getDestTy()->isIntegerTy(64))
      return std::nullopt;

    auto *Shift = llvm::dyn_cast<llvm::BinaryOperator>(Trunc.getOperand(0));
    auto *ShiftAmount = Shift ? llvm::dyn_cast<llvm::ConstantInt>(
                                    Shift->getOperand(1))
                              : nullptr;
    if (!Shift || Shift->getOpcode() != llvm::Instruction::LShr ||
        !ShiftAmount || !ShiftAmount->isOne())
      return std::nullopt;

    auto *Add = llvm::dyn_cast<llvm::BinaryOperator>(Shift->getOperand(0));
    if (!Add || Add->getOpcode() != llvm::Instruction::Add)
      return std::nullopt;
    auto *LeftExtension = llvm::dyn_cast<llvm::ZExtInst>(Add->getOperand(0));
    auto *RightExtension = llvm::dyn_cast<llvm::ZExtInst>(Add->getOperand(1));
    if (!LeftExtension || !RightExtension ||
        !LeftExtension->getSrcTy()->isIntegerTy(64) ||
        !RightExtension->getSrcTy()->isIntegerTy(64))
      return std::nullopt;

    auto *LeftPhi =
        llvm::dyn_cast<llvm::PHINode>(LeftExtension->getOperand(0));
    auto *RightPhi =
        llvm::dyn_cast<llvm::PHINode>(RightExtension->getOperand(0));
    if (!LeftPhi || !RightPhi)
      return std::nullopt;
    if (isOrderedBinarySearch(*LeftPhi, *RightPhi, Trunc))
      return std::pair<llvm::Value *, llvm::Value *>(LeftPhi, RightPhi);
    if (isOrderedBinarySearch(*RightPhi, *LeftPhi, Trunc))
      return std::pair<llvm::Value *, llvm::Value *>(RightPhi, LeftPhi);
    return std::nullopt;
  }

  static bool isZero(const llvm::Value *Value) {
    auto *Constant = llvm::dyn_cast<llvm::ConstantInt>(Value);
    return Constant && Constant->isZero();
  }

  static bool isOne(const llvm::Value *Value) {
    auto *Constant = llvm::dyn_cast<llvm::ConstantInt>(Value);
    return Constant && Constant->isOne();
  }

  static bool isMidpointPlusOne(const llvm::Value *Value,
                                const llvm::TruncInst &Midpoint) {
    auto *Add = llvm::dyn_cast<llvm::BinaryOperator>(Value);
    return Add && Add->getOpcode() == llvm::Instruction::Add &&
           ((Add->getOperand(0) == &Midpoint && isOne(Add->getOperand(1))) ||
            (Add->getOperand(1) == &Midpoint && isOne(Add->getOperand(0))));
  }

  template <typename Predicate>
  static bool isChoiceFrom(const llvm::Value *Value,
                           const llvm::BasicBlock &Block,
                           Predicate IsAllowed) {
    auto *Phi = llvm::dyn_cast<llvm::PHINode>(Value);
    if (!Phi || Phi->getParent() != &Block)
      return IsAllowed(Value);
    for (const llvm::Value *Incoming : Phi->incoming_values())
      if (!IsAllowed(Incoming))
        return false;
    return true;
  }

  static bool edgeRequiresNonzero(const llvm::BasicBlock &From,
                                  const llvm::BasicBlock &To,
                                  const llvm::Value &Bound) {
    const llvm::BasicBlock *GuardTarget = &To;
    auto *Branch = llvm::dyn_cast<llvm::BranchInst>(From.getTerminator());
    if (Branch && Branch->isUnconditional() &&
        Branch->getSuccessor(0) == &To) {
      const llvm::BasicBlock *Predecessor = From.getSinglePredecessor();
      if (!Predecessor || Predecessor == &From)
        return false;
      GuardTarget = &From;
      Branch = llvm::dyn_cast<llvm::BranchInst>(Predecessor->getTerminator());
    }
    auto *Compare = Branch && Branch->isConditional()
                        ? llvm::dyn_cast<llvm::ICmpInst>(Branch->getCondition())
                        : nullptr;
    if (!Compare || (Compare->getPredicate() != llvm::ICmpInst::ICMP_EQ &&
                     Compare->getPredicate() != llvm::ICmpInst::ICMP_NE))
      return false;

    const llvm::Value *ComparableBound = &Bound;
    if (auto *Extension = llvm::dyn_cast<llvm::ZExtInst>(&Bound))
      ComparableBound = Extension->getOperand(0);
    bool TestsBound =
        (Compare->getOperand(0) == ComparableBound &&
         isZero(Compare->getOperand(1))) ||
        (Compare->getOperand(1) == ComparableBound &&
         isZero(Compare->getOperand(0)));
    if (!TestsBound)
      return false;

    bool TrueIsNonzero = Compare->getPredicate() == llvm::ICmpInst::ICMP_NE;
    unsigned NonzeroSuccessor = TrueIsNonzero ? 0 : 1;
    return Branch->getSuccessor(NonzeroSuccessor) == GuardTarget &&
           Branch->getSuccessor(1 - NonzeroSuccessor) != GuardTarget;
  }

  static bool isOrderedBinarySearch(const llvm::PHINode &Minimum,
                                    const llvm::PHINode &Maximum,
                                    const llvm::TruncInst &Midpoint) {
    const llvm::BasicBlock *LoopBlock = Minimum.getParent();
    if (Maximum.getParent() != LoopBlock || Midpoint.getParent() != LoopBlock ||
        Minimum.getNumIncomingValues() != 2 ||
        Maximum.getNumIncomingValues() != 2)
      return false;

    for (unsigned InitialIndex = 0; InitialIndex != 2; ++InitialIndex) {
      const llvm::BasicBlock *InitialBlock =
          Minimum.getIncomingBlock(InitialIndex);
      if (Maximum.getBasicBlockIndex(InitialBlock) < 0)
        continue;
      llvm::Value *InitialMinimum =
          Minimum.getIncomingValueForBlock(InitialBlock);
      llvm::Value *InitialMaximum =
          Maximum.getIncomingValueForBlock(InitialBlock);
      if (!isZero(InitialMinimum) ||
          !edgeRequiresNonzero(*InitialBlock, *LoopBlock, *InitialMaximum))
        continue;

      const llvm::BasicBlock *BackedgeBlock =
          Minimum.getIncomingBlock(1 - InitialIndex);
      if (Maximum.getBasicBlockIndex(BackedgeBlock) < 0)
        continue;
      llvm::Value *NextMinimum =
          Minimum.getIncomingValueForBlock(BackedgeBlock);
      llvm::Value *NextMaximum =
          Maximum.getIncomingValueForBlock(BackedgeBlock);
      if (!isChoiceFrom(NextMinimum, *BackedgeBlock,
                        [&](const llvm::Value *Value) {
                          return Value == &Minimum ||
                                 isMidpointPlusOne(Value, Midpoint);
                        }) ||
          !isChoiceFrom(NextMaximum, *BackedgeBlock,
                        [&](const llvm::Value *Value) {
                          return Value == &Maximum || Value == &Midpoint;
                        }))
        continue;

      auto *Branch =
          llvm::dyn_cast<llvm::BranchInst>(BackedgeBlock->getTerminator());
      auto *Compare = Branch && Branch->isConditional()
                          ? llvm::dyn_cast<llvm::ICmpInst>(Branch->getCondition())
                          : nullptr;
      if (Compare && Compare->getPredicate() == llvm::ICmpInst::ICMP_ULT &&
          Compare->getOperand(0) == NextMinimum &&
          Compare->getOperand(1) == NextMaximum &&
          Branch->getSuccessor(0) == LoopBlock &&
          Branch->getSuccessor(1) != LoopBlock)
        return true;
    }
    return false;
  }

  static void narrowOrderedMidpoint(
      llvm::TruncInst &Trunc, llvm::Value &Minimum, llvm::Value &Maximum,
      const llvm::TargetLibraryInfo &LibraryInfo) {
    llvm::IRBuilder<> Builder(&Trunc);
    Builder.SetCurrentDebugLocation(Trunc.getDebugLoc());
    auto *Delta = llvm::cast<llvm::BinaryOperator>(Builder.CreateSub(
        &Maximum, &Minimum, "aco.midpoint.delta"));
    Delta->setHasNoUnsignedWrap();
    llvm::Value *HalfDelta = Builder.CreateLShr(
        Delta, llvm::ConstantInt::get(Trunc.getType(), 1),
        "aco.midpoint.half-delta");
    auto *NarrowMidpoint = llvm::cast<llvm::BinaryOperator>(Builder.CreateAdd(
        &Minimum, HalfDelta, "aco.midpoint.result"));
    NarrowMidpoint->setHasNoUnsignedWrap();
    Trunc.replaceAllUsesWith(NarrowMidpoint);
    llvm::RecursivelyDeleteTriviallyDeadInstructions(&Trunc, &LibraryInfo);
  }

  static void expandSliceCompareFirstByte(llvm::CallInst &Memcmp,
                                          llvm::CallInst &Ordering) {
    llvm::BasicBlock *EntryBlock = Memcmp.getParent();
    llvm::Function *Function = EntryBlock->getParent();
    llvm::LLVMContext &Context = Function->getContext();
    llvm::DebugLoc DebugLocation = Memcmp.getDebugLoc();

    auto *Select = llvm::cast<llvm::SelectInst>(Ordering.getArgOperand(0));
    auto *IsEqual = llvm::cast<llvm::ICmpInst>(Select->getCondition());
    auto *Extended = llvm::cast<llvm::SExtInst>(Select->getFalseValue());
    auto *LengthDifference =
        llvm::cast<llvm::BinaryOperator>(Select->getTrueValue());
    std::vector<llvm::Instruction *> InstructionsToPreserve;
    for (llvm::Instruction *Instruction = Memcmp.getNextNode();
         Instruction != &Ordering; Instruction = Instruction->getNextNode()) {
      if (Instruction != Extended && Instruction != IsEqual &&
          Instruction != LengthDifference && Instruction != Select &&
          !llvm::isa<llvm::DbgInfoIntrinsic>(Instruction))
        InstructionsToPreserve.push_back(Instruction);
    }

    llvm::BasicBlock *SlowBlock =
        EntryBlock->splitBasicBlock(Memcmp.getIterator(), "aco.slice-cmp.slow");
    llvm::BasicBlock *JoinBlock = SlowBlock->splitBasicBlock(
        std::next(Ordering.getIterator()), "aco.slice-cmp.join");
    llvm::BasicBlock *CheckBlock = llvm::BasicBlock::Create(
        Context, "aco.slice-cmp.check", Function, SlowBlock);
    llvm::BasicBlock *FastBlock = llvm::BasicBlock::Create(
        Context, "aco.slice-cmp.fast", Function, SlowBlock);

    llvm::IRBuilder<> EntryBuilder(EntryBlock->getTerminator());
    EntryBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::Value *FrozenLength = EntryBuilder.CreateFreeze(
        Memcmp.getArgOperand(2), "aco.slice-cmp.length");
    llvm::Value *Nonempty = EntryBuilder.CreateICmpNE(
        FrozenLength, llvm::ConstantInt::get(FrozenLength->getType(), 0),
        "aco.slice-cmp.nonempty");
    EntryBlock->getTerminator()->eraseFromParent();
    EntryBuilder.SetInsertPoint(EntryBlock);
    EntryBuilder.CreateCondBr(Nonempty, CheckBlock, SlowBlock);

    llvm::IRBuilder<> CheckBuilder(CheckBlock);
    CheckBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::Value *LeftByte = CheckBuilder.CreateLoad(
        llvm::Type::getInt8Ty(Context), Memcmp.getArgOperand(0),
        "aco.slice-cmp.left");
    llvm::Value *RightByte = CheckBuilder.CreateLoad(
        llvm::Type::getInt8Ty(Context), Memcmp.getArgOperand(1),
        "aco.slice-cmp.right");
    llvm::Value *FrozenLeft =
        CheckBuilder.CreateFreeze(LeftByte, "aco.slice-cmp.left.frozen");
    llvm::Value *FrozenRight =
        CheckBuilder.CreateFreeze(RightByte, "aco.slice-cmp.right.frozen");
    llvm::Value *FirstEqual = CheckBuilder.CreateICmpEQ(
        FrozenLeft, FrozenRight, "aco.slice-cmp.first-equal");
    CheckBuilder.CreateCondBr(FirstEqual, SlowBlock, FastBlock);

    llvm::IRBuilder<> FastBuilder(FastBlock);
    FastBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::Value *FirstLess = FastBuilder.CreateICmpULT(
        FrozenLeft, FrozenRight, "aco.slice-cmp.first-less");
    llvm::Value *FastOrdering = FastBuilder.CreateSelect(
        FirstLess, llvm::ConstantInt::getSigned(Ordering.getType(), -1),
        llvm::ConstantInt::get(Ordering.getType(), 1),
        "aco.slice-cmp.ordering");
    FastBuilder.CreateBr(JoinBlock);

    Memcmp.setArgOperand(2, FrozenLength);
    Memcmp.setTailCallKind(llvm::CallInst::TCK_None);
    Memcmp.setMetadata("aco.expanded", llvm::MDNode::get(Context, {}));
    Ordering.setTailCallKind(llvm::CallInst::TCK_None);
    llvm::IRBuilder<> JoinBuilder(&*JoinBlock->getFirstInsertionPt());
    JoinBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::PHINode *Result =
        JoinBuilder.CreatePHI(Ordering.getType(), 2, "aco.slice-cmp.result");
    Ordering.replaceAllUsesWith(Result);
    Result->addIncoming(&Ordering, SlowBlock);
    Result->addIncoming(FastOrdering, FastBlock);

    // These instructions were unconditional after memcmp in the source. Move
    // only the matched comparison chain behind the equal-byte branch; retain
    // every unrelated instruction once in the shared continuation so neither
    // the fast nor slow path can bypass its effects.
    llvm::BasicBlock::iterator JoinInsertionPoint =
        JoinBlock->getFirstInsertionPt();
    for (llvm::Instruction *Instruction : InstructionsToPreserve)
      Instruction->moveBefore(*JoinBlock, JoinInsertionPoint);
  }

  static void expandMemcmpFirstByte(llvm::CallInst &Call) {
    llvm::BasicBlock *EntryBlock = Call.getParent();
    llvm::Function *Function = EntryBlock->getParent();
    llvm::LLVMContext &Context = Function->getContext();
    llvm::DebugLoc DebugLocation = Call.getDebugLoc();

    llvm::BasicBlock *SlowBlock =
        EntryBlock->splitBasicBlock(Call.getIterator(), "aco.memcmp.slow");
    llvm::BasicBlock *JoinBlock = SlowBlock->splitBasicBlock(
        std::next(Call.getIterator()), "aco.memcmp.join");
    llvm::BasicBlock *CheckBlock = llvm::BasicBlock::Create(
        Context, "aco.memcmp.check", Function, SlowBlock);
    llvm::BasicBlock *FastBlock = llvm::BasicBlock::Create(
        Context, "aco.memcmp.fast", Function, SlowBlock);

    llvm::IRBuilder<> EntryBuilder(EntryBlock->getTerminator());
    EntryBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::Value *FrozenLength = EntryBuilder.CreateFreeze(
        Call.getArgOperand(2), "aco.memcmp.length");
    llvm::Value *Nonempty = EntryBuilder.CreateICmpNE(
        FrozenLength, llvm::ConstantInt::get(FrozenLength->getType(), 0),
        "aco.memcmp.nonempty");
    EntryBlock->getTerminator()->eraseFromParent();
    EntryBuilder.SetInsertPoint(EntryBlock);
    EntryBuilder.CreateCondBr(Nonempty, CheckBlock, JoinBlock);

    llvm::IRBuilder<> CheckBuilder(CheckBlock);
    CheckBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::Value *LeftByte = CheckBuilder.CreateLoad(
        llvm::Type::getInt8Ty(Context), Call.getArgOperand(0),
        "aco.memcmp.left");
    llvm::Value *RightByte = CheckBuilder.CreateLoad(
        llvm::Type::getInt8Ty(Context), Call.getArgOperand(1),
        "aco.memcmp.right");
    llvm::Value *FrozenLeft =
        CheckBuilder.CreateFreeze(LeftByte, "aco.memcmp.left.frozen");
    llvm::Value *FrozenRight =
        CheckBuilder.CreateFreeze(RightByte, "aco.memcmp.right.frozen");
    llvm::Value *FirstEqual = CheckBuilder.CreateICmpEQ(
        FrozenLeft, FrozenRight, "aco.memcmp.first-equal");
    CheckBuilder.CreateCondBr(FirstEqual, SlowBlock, FastBlock);

    llvm::IRBuilder<> FastBuilder(FastBlock);
    FastBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::Value *ExtendedLeft = FastBuilder.CreateZExt(
        FrozenLeft, Call.getType(), "aco.memcmp.left.extended");
    llvm::Value *ExtendedRight = FastBuilder.CreateZExt(
        FrozenRight, Call.getType(), "aco.memcmp.right.extended");
    llvm::Value *Difference = FastBuilder.CreateNSWSub(
        ExtendedLeft, ExtendedRight, "aco.memcmp.difference");
    FastBuilder.CreateBr(JoinBlock);

    Call.setArgOperand(2, FrozenLength);
    Call.setTailCallKind(llvm::CallInst::TCK_None);
    Call.setMetadata("aco.expanded", llvm::MDNode::get(Context, {}));
    llvm::IRBuilder<> JoinBuilder(&*JoinBlock->getFirstInsertionPt());
    JoinBuilder.SetCurrentDebugLocation(DebugLocation);
    llvm::PHINode *Result =
        JoinBuilder.CreatePHI(Call.getType(), 3, "aco.memcmp.result");
    Call.replaceAllUsesWith(Result);
    Result->addIncoming(llvm::ConstantInt::get(Call.getType(), 0), EntryBlock);
    Result->addIncoming(&Call, SlowBlock);
    Result->addIncoming(Difference, FastBlock);
  }
};

bool addAcoPipeline(llvm::ModulePassManager &ModulePasses,
                    llvm::StringRef Name) {
  bool EnableThreeWayCompare = Name == "aco-passes";
  bool EnableSliceComparisons =
      Name == "aco-passes" || Name == "aco-slice-comparison-only" ||
      Name == "aco-key-comparisons";
  bool EnableMidpoints = Name == "aco-passes" || Name == "aco-midpoint-only" ||
                         Name == "aco-key-comparisons";
  if (!EnableThreeWayCompare && !EnableSliceComparisons && !EnableMidpoints)
    return false;

  // The slice matcher consumes an llvm.scmp use chain. Run it before the
  // general scmp switch lowering so the aggregate pipeline retains both
  // independently proved optimizations.
  if (EnableSliceComparisons || EnableMidpoints)
    ModulePasses.addPass(llvm::createModuleToFunctionPassAdaptor(
        KeyholePass(EnableSliceComparisons, EnableMidpoints)));
  if (EnableThreeWayCompare)
    ModulePasses.addPass(
        llvm::createModuleToFunctionPassAdaptor(ThreeWayCompareSwitchPass()));
  return true;
}

void addAcoPasses(llvm::ModulePassManager &ModulePasses) {
  bool Added = addAcoPipeline(ModulePasses, "aco-passes");
  assert(Added && "the aggregate ACO pipeline must exist");
}

llvm::PassPluginLibraryInfo getPluginInfo() {
  return {
      LLVM_PLUGIN_API_VERSION,
      "aco-optimizer",
      LLVM_VERSION_STRING,
      [](llvm::PassBuilder &Builder) {
        Builder.registerPipelineParsingCallback(
            [](llvm::StringRef Name, llvm::ModulePassManager &ModulePasses,
               llvm::ArrayRef<llvm::PassBuilder::PipelineElement>) {
              return addAcoPipeline(ModulePasses, Name);
            });
      },
  };
}

} // namespace aco

extern "C" LLVM_ATTRIBUTE_WEAK llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return aco::getPluginInfo();
}
