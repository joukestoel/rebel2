module rebel::Plugin

import rebel::lang::Syntax;
import rebel::lang::Parser;
import rebel::lang::TypeChecker;
import rebel::lang::DependencyAnalyzer;

import rebel::checker::ModelChecker;
import rebel::checker::Trace;
 
import util::IDE;
import util::Prompt; 

import salix::App;
import rebel::vis::ModuleVis;
import rebel::vis::TraceVis;

import ParseTree;
import Location;
import util::PathUtil; 

import IO; 

void main() {
  str REBEL2_LANGUAGE = "Rebel2 Language";
  registerLanguage(REBEL2_LANGUAGE,"rebel", parseModule);
  
  registerContributions(REBEL2_LANGUAGE, getRebelContributions());
}

alias VisConfig = tuple[int port, tuple[void () serve, void () stop] app];

set[Contribution] getRebelContributions() {

  Content runCheck(Module m, loc selection, int solverTimeout = 30 * 1000) {
    if (/Check chk <- m.parts, isContainedIn(selection, chk@\loc)) {
      println("Running check");
      
      PathConfig pcfg = defaultPathConfig(m@\loc.top);
      TypeCheckerResult tr = typeCheckModule(m);
      
      Trace t = performCheck(chk, m, tr.tm, tr.depGraph, pcfg = pcfg, saveIntermediateFiles = false, solverTimeout = solverTimeout);
      
      switch(t) {
        case noTrace(solverTimeout()): {
          alert("Solver timed out. Please simplify the check");
          throw "Solver timed out";
        }
        case noTrace(noSolutionFound()): {
          alert("No trace found. Check not satisfiable for the given configuration");
          throw "No trace found";
        }
        default: return createTraceVis("<chk.name>", t);
      } 
    } 
  }
  
  Content showModuleVis(Module _, loc file) = createStateMachineVis(file.top);

  TypeCheckerResult typeCheckModule(Module m) {
    PathConfig pcfg = defaultPathConfig(m@\loc.top);
            
    Graph[RebelDependency] depGraph = calculateDependencies(m, pcfg);
    TypeCheckerResult tr = checkModule(m, depGraph, pcfg, saveTModels = true, refreshRoot = true, debug = false);
    
    return tr;
  }
  
  return {
    annotator(Module (Module m) {
      TypeCheckerResult tr = typeCheckModule(m);
      
      annotatedMod = m[@messages= {*tr.tm.messages}];
      annotatedMod = annotatedMod[@hyperlinks=tr.tm.useDef];
      
      return annotatedMod;
    }),
    syntaxProperties(#start[Module]),
    popup(
      menu("Rebel actions", [
        interaction("Visualize", showModuleVis), 
        interaction("Run checker (30s timeout)", runCheck),
        interaction("Run checker (custom timeout)", Content (Module m, loc selection) { 
          return runCheck(m,selection, solverTimeout = promptForInt("Enter the desired solver timeout in seconds\n(0 means no timeout)") * 1000);
        })
      ])
    )   
  };
}