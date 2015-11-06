use stackcode::*;
use stackcode::SCode::*;
use gc::*;
use super::*;
use super::object::*;
// use super::object::_Object::*;
use super::classty::*;
use super::primty::*;


pub fn interprete(inst: &SCode,
                  locals: &mut Vec<Gc<_Object>>,
                  stack: &GcCell<Vec<Gc<_Object>>>,
                  env: &Gc<Env>,
                  globals: &mut Vec<Gc<_Object>>) {

    println!("interpreting: {:?}", inst);

    match inst {
        &PUSHL(x) => {
            stack.borrow_mut().push(locals[x as usize].clone());
        },
        &PUSHG(x) => {
            stack.borrow_mut().push(globals[x as usize].clone());
        },
        &POPG(x) => {
            let i = x as usize;
            if GLOBAL_MAXSIZE > i {
               globals[i] = stack.borrow_mut().pop().unwrap(); 
            } else {
                assert!(false, "globals is not as many as {}", i + 1);
            }
        },
        &ADD => {
            let a1 = stack.borrow_mut().pop().unwrap();
            let a2 = stack.borrow_mut().pop().unwrap();
            let ret = a1.call("add", vec![a2], env, globals);
            stack.borrow_mut().push(ret);
        },
        &NEW(x) => {
            let obj = env.__new__(x as usize);
            stack.borrow_mut().push(obj);
        },
        &PUSH_INT(i) => {
            let obj = Int_ty::new(i);
            stack.borrow_mut().push(obj);
        },
        &PUSH_STR(ref s) => {
            let obj = String_ty::new(s.clone());
            stack.borrow_mut().push(obj);
        },
        &PRINT => {
            let x = stack.borrow_mut().pop().unwrap();
            x.call("__print__", vec![], env, globals);
        },
        &POPL(x) => {
            let i = x as usize;
            if GLOBAL_MAXSIZE > i {
               locals[i] = stack.borrow_mut().pop().unwrap(); 
            } else {
                assert!(false, "locals is not as many as {}", i + 1);
            }
        },
        &PUSHA(x) => {
            let obj = stack.borrow_mut().pop().unwrap();
            stack.borrow_mut().push((obj.access_i(x as usize)));
        },
        &PUSHASTR(ref s) => {
            let obj = stack.borrow_mut().pop().unwrap();
            stack.borrow_mut().push(obj.access(s));
        },
        _ => {
            assert!(false, "illegal instruction: {:?}", inst);
        }
    }
}