module analysis::CommonTranslationFunctions

import lang::Syntax;

import String;

data State 
  = uninitialized()
  | finalized()
  | state(str name)
  ;

@memo
str getLowerCaseSpecName(Spec spc) = toLowerCase("<spc.name>");

@memo
str getCapitalizedSpecName(Spec spc) = capitalize("<spc.name>");

@memo
str getPrimStateVectorName(Spec spc) = "StateVector<getCapitalizedSpecName(spc)>Primitives";

@memo
set[Spec] lookupSpecs(rel[Spec spc, str instance, State initialState] instances) = {i.spc | i <- instances}; 

@memo
set[str] lookupStates(Spec spc) 
  = {"state_<specName>_<st>" | /lang::Syntax::State st <- spc.states, st has name} 
  + {"state_uninitialized", "state_finalized"} 
  when str specName := toLowerCase("<spc.name>");

@memo
set[str] lookupInstances(Spec spc, rel[Spec spc, str instance, State _] instances) 
  = instances[spc]<0>;

@memo
set[str] lookupEventNames(Spec spc)
  = {"event_<specName>_<ev>" | Event event <- lookupEvents(spc), str ev := replaceAll("<event.name>", "::", "_")}
  when str specName := toLowerCase("<spc.name>");

@memo
set[Event] lookupEvents(Spec spc) = {e | /Event e := spc.events};

@memo
list[Field] lookupPrimitiveFields(Spec s) = [f | /Field f <- s.fields, isPrim(f.tipe)];

@memo
list[str] lookupPrimitiveFieldNames(Spec s) = ["<f.name>" | Field f <- lookupPrimitiveFields(s)];

@memo
list[FormalParam] lookupPrimitiveParams(Event e) = [p | /FormalParam p <- e.params, isPrim(p.tipe)];

bool isPrim((Type)`Integer`) = true;
default bool isPrim(Type _) = false;