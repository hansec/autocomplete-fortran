## 0.7.1

### Improvements
* Add support for additional file extensions to match the language-fortran package- fixes issue [#3](https://github.com/hansec/autocomplete-fortran/issues/3)

## 0.7.0

### Improvements
* Improve parsing speed during initial indexing and full rebuilds (initial indexing should now be almost instant)
* Detect and handle line continuation with context based suggestion filtering (ex. USE statements)

## 0.6.1

### Fixes
* Catch invalid or inaccessible module directory paths- fixes issue [#2](https://github.com/hansec/autocomplete-fortran/issues/2)
* Fix parsing errors when a file is saved while adding a new scope

## 0.6.0

### Improvements
* Provide array dimensions in suggestions
* Add context filtering when only user-defined type names are valid

## 0.5.0

### Improvements
* Track child classes and update fields when parent class is updated
* Trigger reparsing when a buffer is saved
* Improve debug output for diagnosing parser failures

## Fixes
* Fix issue [#1](https://github.com/hansec/autocomplete-fortran/issues/1)- parsing error with "non-module" interface procedures

## 0.4.0

### Improvements
* Add minimum word size before suggestions are provided
* Add suggestion filtering for USE statements (restrict to modules and module members)
* Disable suggestions in quoted strings
* Reduce parsing frequency by preventing local buffer AST updates until edits on a line have completed
* Refactor FORTRAN parser to improve accuracy/robustness

## Fixes
* Fix parsing errors when adding a scope to the current buffer (automatically close scopes when parsing buffer)
* Fix bug in parsing when generic "END" statement was followed by a comment
* Fix bug in "GoTo Declaration" when declaration is in current buffer which is not included in the parsing directories

## 0.3.0

### Improvements
* Add return type to function suggestions
* Add POINTER/ALLOCATABLE information to variable suggestions
* Indicate optional subroutine arguments ("arg=arg")
* Provide argument list for procedure pointers with defined interfaces
* Improve accuracy/robustness of scope identification for user-defined type fields
* Improve speed by searching each imported module only once
* Add keybinding for "GoTo Declaration"

### Fixes
* Remove class "self" argument from type bound procedures
* Fix issue with lower vs upper case in user-defined type fields
* Restrict "GoTo Declaration" context menu to FORTRAN source files

## 0.2.0
* Add initial support for fixed-format grammar
* Add GoTo Declaration
* Improve parser error handling/reporting

## 0.1.1
* Update listed dependencies to include `language-fortran`

## 0.1.0 - First Release
* Initial release
