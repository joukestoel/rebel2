module rebel::lang::SpecSyntax

import rebel::lang::CommonSyntax;

syntax Part 
  = Spec spc
  | Enum enum
  ;

syntax Spec = "spec" Id name Fields? fields Constraints? constraints Event* events States? states;

syntax Fields
  = {Field ","}+ fields ";"
  ;

syntax Field
  = Id name ":" Type tipe
  ;
  
syntax Constraints
  = {Constraint ","}+ constraints ";"
  ;
  
syntax Constraint
  =  "unique" {Id ","}+ fields
  ;
  
syntax Event
  = Modifier? modi "event" Id name "(" {FormalParam ","}* params ")" EventBody body 
  ;

syntax Modifier
  = "init"
  | "internal"
  ;
  
syntax FormalParam
  = Id name ":" Type tipe
  ;
  
syntax EventBody
  = Pre? pre Post? post EventVariant* variants
  ;
    
syntax Pre
  = "pre" ":" {Formula ","}* formulas ";"
  ;

syntax Post
  = "post" ":" {Formula ","}* formulas ";"
  ;

syntax EventVariant
  = "variant" Id name EventVariantBody body
  ;  

syntax EventVariantBody
  = Pre? pre Post? post
  ; 
  
syntax States
  = "states" ":" Transition* trans
  ;
  
syntax Transition
  = State from "-\>" State to ":" {TransEvent ","}+ events ";"
  | State super InnerStates? inner "{" Transition* trans "}"
  ;

syntax InnerStates
  = "[" {State ","}+ states "]"
  ;
  
syntax State
  = Id name
  | "(*)"
  ;
  
syntax TransEvent
  = Id event \ "empty"
  | Id event "::" Id variant
  | "empty"
  ;  
 
syntax Lit
  = "this"
  ; 
 
syntax Enum = "enum" Id {Id ","}+ values ";";
 
keyword Keywords = "spec"
                 | "failure" 
                 | "success" 
                 | "event" 
                 | "pre" 
                 | "post"
                 | "init"
                 | "states"
                 | "enum"
                 | "variant"
                 ;
 