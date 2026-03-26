isMiddleDown := false

F4::{
	global isMiddleDown
	if !isMiddleDown {
		isMiddleDown := true
		MouseClick("Middle", 0, 0, 1, 0, "D") ; Hold middle button down
	} else {
		isMiddleDown := false
		MouseClick("Middle", 0, 0, 1, 0, "U") : 
	}
}