module analysis::allealle::EventTranslator

import analysis::allealle::CommonTranslationFunctions;
import analysis::allealle::SyncedEventGraphBuilder;
import rebel::lang::SpecSyntax;
import rebel::lang::SpecTypeChecker;

import String;
import IO;
import Set;
import List;
import ParseTree;

data Context = ctx(map[str var, str relation] varLookup, void () incNrOfChangedInstances, int () getNrOfChangedInstances, Config cfg);

str constructTransitionFunction(Spec spc, Graph[SyncedWith] syncDep, Config cfg) {
  list[str] getEventParams(Event e) { 
    list[str] actuals = ["step", "inst"];
    
    for (/FormalParam p <- e.params) {
      actuals += "(step ⨝ ParamEvent<getCapitalizedSpecName(spc)><getCapitalizedEventName(e)><getCapitalizedParamName(p)>)[<p.name>]";
    }

    return actuals;
  }
  
  str buildTransCond(Event e) {
    tuple[set[str] names, list[str] syncs] lets = syncedInstanceRels(spc, e, "inst", syncDep, cfg.tm);
    lets.names += {"inst"};
    if (lets.syncs != []) lets.syncs = ["cur = step[cur-\>config]"] + lets.syncs;
    
    return "(event<getCapitalizedSpecName(spc)><getCapitalizedEventName(e)>[<intercalate(",", getEventParams(e))>] ∧
           '(step ⨝ raisedEvent)[event] = Event<getCapitalizedSpecName(spc)><getCapitalizedEventName(e)> ∧
           '<if (lets.syncs != []) {>let <intercalate(", ", lets.syncs)> | <}>(changedInstance ⨝ step)[instance] ⊆ <intercalate(" ∪ ", [*lets.names])>)";
  }
  
  list[str] eventTrans = [buildTransCond(e) | Event e <- lookupEvents(spc), !isFrameEvent(e)];
  
  return "pred possibleTransitions<getCapitalizedSpecName(spc)>[step: (cur:id, nxt:id)] 
         '  = ∀ inst ∈ (Instance ⨝ <getCapitalizedSpecName(spc)>)[instance] |
         '    (some inst ∩ ((raisedEvent ⨝ step)[instance]) ⇔ (
         '      <intercalate("\n∨\n", eventTrans)>
         '    ))
         '    ∧
         '    (no inst ∩ (changedInstance ⨝ step)[instance] ⇔ frame<getCapitalizedSpecName(spc)>[step, inst])
         '"; 
}

private tuple[set[str],list[str]] syncedInstanceRels(Spec s, Event e, str instRel, Graph[SyncedWith] syncDep, TModel tm) {
  bool isField(Expr exp) {
    visit (exp) {
      case (Expr)`this.<Id field>`: return true;
    }
    return false;
  }
  
  list[str] syncLets = [];
  set[str] relNames = {};
  
  for (SyncedWith synced <- syncDep[<s,e>]) {
    if (/f:(Formula)`<Expr exp>.<Id ev>(<{Expr ","}* args>)` := e.body, "<ev>" == "<synced.e.name>", getSpecTypeName(exp,tm) == "<synced.s.name>") {
      str fieldName = getFieldName(exp);      
      relNames += fieldName;      
      
      if (isField(exp)) {
        syncLets += "<fieldName> = (<getCapitalizedSpecName(s)><capitalize(fieldName)> |x| cur |x| <instRel>)[<fieldName>-\>instance]";
      } else {
        syncLets += "<fieldName> = (ParamEvent<getCapitalizedSpecName(s)><getCapitalizedEventName(e)><capitalize(fieldName)> |x| step)[<fieldName>-\>instance]";
      }
      
      if (<n,sl> := syncedInstanceRels(synced.s, synced.e, fieldName, syncDep, tm)) {
        syncLets += sl;
        relNames += n;
      } 
      
    } else {
      throw "Unable to find syncing event expression in event body";
    }   
  }
  
  return <relNames, syncLets>;
}

str translateEventsToPreds(Spec spc, Config cfg) =
  "<for (Event e <- events) {><if (isFrameEvent(e)) {><translateFrameEvent(spc, e, getLowerCaseSpecName(spc), cfg)><} else {><translateEventToPred(spc, e, getLowerCaseSpecName(spc), cfg)><}>
  '<}>"
  when set[Event] events := lookupEvents(spc);

private bool isFrameEvent(Event e) = "<e.name>" == "__frame";

str translateEventToPred(Spec spc, Event event, str instanceRel, Config cfg) {
  list[str] letRels = buildLetVars(spc, event, instanceRel, cfg);
  list[str] paramVars = ["step:(cur:id, nxt:id)", "<getLowerCaseSpecName(spc)>: (instance:id)"] + buildParamVars(event, cfg);
  
  return "pred event<getCapitalizedSpecName(spc)><getCapitalizedEventName(event)>[<intercalate(", ", paramVars)>]
         '  = let <intercalate(",\n", letRels)> |
         '    <translateEventBody(spc, event, ctx((), () {;}, int () {return -1;}, cfg))>
         '";
}

str translateFrameEvent(Spec spc, Event frameEvent, str instRel, Config cfg) {
  list[str] letRels = buildLetVars(spc, frameEvent, instRel, cfg);
  
  return "pred frame<getCapitalizedSpecName(spc)>[step: (cur:id, nxt:id), <getLowerCaseSpecName(spc)>: (instance:id)] 
         '  = let <intercalate(",\n", letRels)> | (
         '    nxtState = curState ∧
         '    (
         '      curState ⊆ uninitialized ∨ 
         '      (<translatePost(frameEvent, ctx((), void () {;}, int () {return -1;}, cfg))>)
         '    )
         '  )
         '";
}

private list[str] buildLetVars(Spec spc, Event event, str instRel, Config cfg) {
  str renamePrimField(Field f, str prefix) = "<f.name>-\><prefix><getCapitalizedFieldName(f)>";
  list[str] letRels = ["cur = step[cur-\>config]", "nxt = step[nxt-\>config]", "curState = (instanceInState ⨝ cur ⨝ <instRel>)[state]", "nxtState = (instanceInState ⨝ nxt ⨝ <instRel>)[state]"];
  
  for (/Field f <- spc.fields) {
    str relName = "<getCapitalizedSpecName(spc)><getCapitalizedFieldName(f)>";

    letRels += "cur<getCapitalizedFieldName(f)> = (cur ⨝ <relName> ⨝ <instRel>)<if (isPrim(f.tipe,cfg.tm)) {>[<renamePrimField(f, "cur")>]<} else {>[<f.name>]<}>";
    letRels += "nxt<getCapitalizedFieldName(f)> = (nxt ⨝ <relName> ⨝ <instRel>)<if (isPrim(f.tipe,cfg.tm)) {>[<renamePrimField(f, "nxt")>]<} else {>[<f.name>]<}>";
  }    

  return letRels;
}

private list[str] buildParamVars(Event event, Config cfg) {
  list[str] varDefs = [];
  
  for (/FormalParam p <- event.params) {
    varDefs += "param<getCapitalizedParamName(p)>: (<p.name>:<convertType(p.tipe)>)";
  }
  
  return varDefs;
} 

private str translateEventBody(Spec spc, Event event, Context ctx) {
  str pre = translatePre(event, ctx);
  str post = translatePost(event, ctx);

  return  "( 
          '  <pre> <if (pre != "") {> ∧ <}>
          '  <post> <if (post != "") {> ∧ <}>
          '  // Generic event conditions
          '  forceState[curState, nxtState, Event<getCapitalizedSpecName(spc)><capitalize("<event.name>")>] ∧
          '  // Make sure this instance is in the change set
          '  <getLowerCaseSpecName(spc)> ⊆ (changedInstance ⨝ step)[instance]
          ')";
}

private str translatePre(Event event, Context ctx) 
  = "// Preconditions 
    '<intercalate(" ∧\n",[translate(f,ctx) | f <- pre.formulas])>"
    when /Pre pre := event;

private default str translatePre(Event event, Context ctx) = "";     

private str translatePost(Event event, Context ctx) 
  = "// Postconditions
    '<intercalate(" ∧\n", [translate(f, ctx) | Formula f <- post.formulas])>"
    when /Post post := event;

private default str translatePost(Event event, Context ctx) = "";     

str translate((Formula)`(<Formula f>)`, Context ctx) = "(<translate(f,ctx)>)";

str getFieldName(Expr expr) = visit(expr) {
  case (Expr)`this.<Id field>`: return "<field>";
  case (Expr)`<Id field>`: return "<field>";
};

str translate((Formula)`<Expr spc>.<Id event>(<{Expr ","}* params>)`, Context ctx) { 
  str relOfSync = translate(spc, ctx);
  
  //ctx.addChangedInstance("<relOfSync>[<getFieldName(spc)>-\>instance]");
  
  Spec syncedSpec = getSpecByType(spc, ctx.cfg.instances, ctx.cfg.tm);
  Event syncedEvent = lookupEventByName("<event>", syncedSpec);

  // Fix synced event param values
  list[str] actuals = ["step", "<relOfSync>[<getFieldName(spc)> as instance]"];
  
  list[FormalParam] formals = [p | FormalParam p <- syncedEvent.params];
  list[Expr] args = [a | Expr a <- params];
   
  for (int i <- [0..size(formals)]) {
    if ((Expr)`<Int ii>` := args[i]) {
      actuals += "__C<ii>[val-\><formals[i].name>]"; 
    } else {
      actuals += "<translate(args[i], ctx)>";
    }
  }
   
  return "event<getCapitalizedSpecName(syncedSpec)><getCapitalizedEventName(syncedEvent)>[<intercalate(", ", actuals)>]";  
}  

str getSpecTypeName(Expr expr, TModel tm) = name when specType(str name) := getType(expr, tm);
default str getSpecTypeName(Expr expr, TModel tm) { throw "Expression `<expr>` is not a Spec Type"; }

str translate(f: (Formula)`<Expr lhs> is <Id state>`, Context ctx) {
  str specOfLhs = getSpecTypeName(lhs, ctx.cfg.tm);
  str fieldName = getFieldName(lhs);
   
  str specRel = isParam(lhs, ctx.cfg.tm) ?
    "param<capitalize(fieldName)>[<fieldName>-\>instance]" : 
    "cur<capitalize(fieldName)>[<fieldName>-\>instance])";  
  
  str stateRel = "<state>" == "initialized" ?
    "initialized" :
    "State<capitalize(specOfLhs)><capitalize("<state>")>";
    
  return "inState[cur, <specRel>, <stateRel>]";    
} 

str translate((Formula)`<Formula lhs> && <Formula rhs>`,    Context ctx) = "(<translate(lhs,ctx)> ∧ <translate(rhs,ctx)>)";
str translate((Formula)`<Formula lhs> || <Formula rhs>`,    Context ctx) = "(<translate(lhs,ctx)> ∨ <translate(rhs,ctx)>)";
str translate((Formula)`<Formula lhs> =\> <Formula rhs>`,   Context ctx) = "(<translate(lhs,ctx)> ⇒ <translate(rhs,ctx)>)";
str translate((Formula)`<Formula lhs> \<=\> <Formula rhs>`, Context ctx) = "(<translate(lhs,ctx)> ⇔ <translate(rhs,ctx)>)";

str translate((Formula)`<Expr lhs> = <Expr rhs>`,   Context ctx)  = translateEq(lhs, rhs, "=", ctx);
str translate((Formula)`<Expr lhs> != <Expr rhs>`,   Context ctx) = translateEq(lhs, rhs, "!=", ctx);

str translate((Formula)`<Expr lhs> \< <Expr rhs>`,  Context ctx) = translateRestrictionEquality(lhs, rhs, "\<",  ctx);
str translate((Formula)`<Expr lhs> \<= <Expr rhs>`, Context ctx) = translateRestrictionEquality(lhs, rhs, "\<=", ctx);
str translate((Formula)`<Expr lhs> \>= <Expr rhs>`, Context ctx) = translateRestrictionEquality(lhs, rhs, "\>=", ctx);
str translate((Formula)`<Expr lhs> \> <Expr rhs>`,  Context ctx) = translateRestrictionEquality(lhs, rhs, "\>",  ctx);

str translateEq(Expr lhs, Expr rhs, str op, Context ctx) {
  // Is it equality on attributes?
  if (isAttributeType(lhs, ctx.cfg.tm) && isAttributeType(rhs, ctx.cfg.tm)) {
    // it is equality on attributes
    return translateRestrictionEquality(lhs, rhs, op, ctx);
  } else {
    return translateRelEquality(lhs, rhs, op, ctx);
  }
}

str translateRelEquality(Expr lhs, Expr rhs, str op, Context ctx) = "<translate(lhs, ctx)> <op> <translate(rhs, ctx)>"; 

str translateRestrictionEquality(Expr lhs, Expr rhs, str operator, Context ctx) {
  set[str] refRels = findReferencedRels(lhs, ctx) + findReferencedRels(rhs, ctx);

  return "(some (<intercalate(" ⨯ ", [*refRels])>) where (<translateAttr(lhs,ctx)> <operator> <translateAttr(rhs,ctx)>))";
}  

set[str] findReferencedRels(Expr expr, Context ctx) {
  set[str] rels = {};
  set[loc] nr = {};

  top-down visit(expr) {
    case (Expr)`this.<Id field>` : {if (field@\loc notin nr) rels += "cur<capitalize("<field>")>";} 
    case (Expr)`this.<Id field>'`: {rels += "nxt<capitalize("<field>")>"; nr += field@\loc;}
    case (Expr)`<Id param>`      : rels += "param<capitalize("<param>")>";  // event param is referenced
  }
  
  return rels;
}

//list[str] findReferencedRels(set[Reference] refs, Context ctx) {
//  list[str] refRels = [];
//  
//  if (cur() in refs) {
//    refRels += "curFlat"; //ctx.varLookup["cur_flattened"];
//  }
//  if (next() in refs) {
//    refRels += "nxtFlat"; //ctx.varLookup["nxt_flattened"];
//  }
//  if (param() in refs) {
//    refRels += "paramFlat"; //ctx.varLookup["params_flattened"];
//  }
//  
//  return refRels; 
//}
  
str translate((Expr)`(<Expr e>)`, Context ctx) = "(<translate(e,ctx,prefix)>)"; 

str translate((Expr)`<Id id>`, Context ctx) = "param<capitalize("<id>")>";
str translate((Expr)`this.<Id id>`, Context ctx) = "cur<capitalize("<id>")>[<id>]";
str translate((Expr)`this.<Id id>'`, Context ctx) = "nxt<capitalize("<id>")>[<id>]";

str translateAttr((Expr)`(<Expr e>)`, Context ctx) = "(<translateAttr(e,ctx,prefix)>)"; 
str translateAttr((Expr)`<Id id>`, Context ctx) = "<id>";
str translateAttr((Expr)`this.<Id id>`, Context ctx) = "cur<capitalize("<id>")>";
str translateAttr((Expr)`this.<Id id>'`, Context ctx) = "nxt<capitalize("<id>")>";

str translateAttr((Expr)`now`, Context ctx) { throw "Not yet supported"; }
str translateAttr((Expr)`<Lit l>`, Context ctx) = translate(l);

str translateAttr((Expr)`- <Expr e>`, Context ctx) = "-<translateAttr(e,ctx)>";
str translateAttr((Expr)`<Expr lhs> * <Expr rhs>`, Context ctx) = "<translateAttr(lhs,ctx)> * <translateAttr(rhs,ctx)>";
str translateAttr((Expr)`<Expr lhs> \\ <Expr rhs>`, Context ctx) = "<translateAttr(lhs,ctx)> \\ <translateAttr(rhs,ctx)>";
str translateAttr((Expr)`<Expr lhs> + <Expr rhs>`, Context ctx) = "<translateAttr(lhs,ctx)> + <translateAttr(rhs,ctx)>";
str translateAttr((Expr)`<Expr lhs> - <Expr rhs>`, Context ctx) = "<translateAttr(lhs,ctx)> - <translateAttr(rhs,ctx)>";

default str translate(Expr e, Context ctx) { throw "Can not translate expression `<e>` at location <e@\loc>"; }

str translate((Lit)`<Int i>`) = "<i>";
str translate((Lit)`<StringConstant s>`) { throw "Not yet supported"; }
