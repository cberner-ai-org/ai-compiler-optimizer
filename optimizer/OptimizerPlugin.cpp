#include "llvm/Config/llvm-config.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/raw_ostream.h"

#include <cassert>
#include <cstdlib>

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
        !Compare->hasOneUse() || !Compare->getType()->isIntegerTy(8) ||
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
  llvm::PreservedAnalyses run(llvm::Function &Function,
                              llvm::FunctionAnalysisManager &) {
    if (std::getenv("ACO_OPTIMIZER_TRACE"))
      llvm::errs() << "aco-keyhole: ran on " << Function.getName() << '\n';

    // This is the integration seam for future solver-proven peephole rewrites.
    // Until then, preserve both the IR and every cached analysis.
    return llvm::PreservedAnalyses::all();
  }
};

void addAcoPasses(llvm::ModulePassManager &ModulePasses) {
  ModulePasses.addPass(
      llvm::createModuleToFunctionPassAdaptor(ThreeWayCompareSwitchPass()));
  ModulePasses.addPass(
      llvm::createModuleToFunctionPassAdaptor(KeyholePass()));
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
              if (Name != "aco-passes")
                return false;

              addAcoPasses(ModulePasses);
              return true;
            });
      },
  };
}

} // namespace aco

extern "C" LLVM_ATTRIBUTE_WEAK llvm::PassPluginLibraryInfo
llvmGetPassPluginInfo() {
  return aco::getPluginInfo();
}
