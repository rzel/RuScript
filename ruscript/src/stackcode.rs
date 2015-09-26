use super::*;


#[derive(Trace)]
pub enum SCode {
    PUSHL(ObjIdentTy),
    PUSHG(ObjIdentTy),
    ADD, // "Add" two objects together
    CALL(ObjIdentTy, String, ArgIdentTy), // Receiver, Method name, and number of arguments
    RET, // return the stack top,

    // Extended
    NEW(ObjIdentTy), // Construct and push constructed object on stack
    PUSH_INT(int), // Push a literal on stack
    PUSH_STR(Box<String>), // Push string of attribute on stack,

    FRMSTT, // Indicate code literal mode
    FRMEND(int), // End code literal mode, indicate the number of globals, and push the frame object on stack
    CLASS(int, int), // Constructor class with n attributes and n methods
    
    PRINT,
}
