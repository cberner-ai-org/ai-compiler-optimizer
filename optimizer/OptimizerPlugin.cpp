#include "llvm/Config/llvm-config.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/PassManager.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Plugins/PassPlugin.h"
#include "llvm/Support/Compiler.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdlib>

namespace aco {

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
  // Add accepted custom optimization passes here in pipeline order.
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
