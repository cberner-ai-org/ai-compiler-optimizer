#include "llvm/ADT/StringRef.h"
#include "llvm/Analysis/TargetLibraryInfo.h"
#include "llvm/IR/PassManager.h"
#include "llvm/IR/Verifier.h"
#include "llvm/IRReader/IRReader.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/raw_ostream.h"

namespace aco {
bool addAcoPipeline(llvm::ModulePassManager &, llvm::StringRef);
}

int main(int ArgumentCount, char **Arguments) {
  if (ArgumentCount != 3 && ArgumentCount != 4) {
    llvm::errs() << "usage: aco-optimizer-test-driver INPUT.ll PIPELINE "
                    "[--make-fake-scmp]\n";
    return 2;
  }

  llvm::LLVMContext Context;
  llvm::SMDiagnostic Error;
  std::unique_ptr<llvm::Module> Module =
      llvm::parseIRFile(Arguments[1], Error, Context);
  if (!Module) {
    Error.print(Arguments[0], llvm::errs());
    return 1;
  }
  if (llvm::verifyModule(*Module, &llvm::errs()))
    return 1;

  bool MakeFakeScmp = ArgumentCount == 4;
  if (MakeFakeScmp) {
    if (llvm::StringRef(Arguments[3]) != "--make-fake-scmp") {
      llvm::errs() << "unknown test mutation: " << Arguments[3] << '\n';
      return 2;
    }
    llvm::Function *Ordering = Module->getFunction("llvm.scmp.i8.i64");
    if (!Ordering) {
      llvm::errs() << "test mutation requires llvm.scmp.i8.i64\n";
      return 2;
    }
    // LLVM's parser canonicalizes llvm.scmp overload suffixes and its verifier
    // rejects a renamed intrinsic. Mutate only after verifying the fixture so
    // this structural test can still exercise the matcher's name boundary.
    Ordering->setName("llvm.scmp.i8.i64.fake");
  }

  llvm::LoopAnalysisManager LoopAnalyses;
  llvm::FunctionAnalysisManager FunctionAnalyses;
  llvm::CGSCCAnalysisManager CGSCCAnalyses;
  llvm::ModuleAnalysisManager ModuleAnalyses;
  llvm::PassBuilder Builder;
  Builder.registerModuleAnalyses(ModuleAnalyses);
  Builder.registerCGSCCAnalyses(CGSCCAnalyses);
  Builder.registerFunctionAnalyses(FunctionAnalyses);
  Builder.registerLoopAnalyses(LoopAnalyses);
  FunctionAnalyses.registerPass(
      [&] { return llvm::TargetLibraryAnalysis(); });
  Builder.crossRegisterProxies(LoopAnalyses, FunctionAnalyses, CGSCCAnalyses,
                               ModuleAnalyses);

  llvm::ModulePassManager Passes;
  if (!aco::addAcoPipeline(Passes, Arguments[2])) {
    llvm::errs() << "unknown ACO pipeline: " << Arguments[2] << '\n';
    return 2;
  }
  Passes.run(*Module, ModuleAnalyses);
  // A compiler pipeline may contain an extension point more than once. Running
  // the pass twice makes its idempotence part of the focused regression test.
  Passes.run(*Module, ModuleAnalyses);
  if (!MakeFakeScmp && llvm::verifyModule(*Module, &llvm::errs()))
    return 1;
  Module->print(llvm::outs(), nullptr);
}
