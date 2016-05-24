# autocomplete-fortran package

This package provides autocomplete suggestions and "Go To Declaration" support for FORTRAN code using [autocomplete-plus](https://atom.io/packages/autocomplete-plus).

*Note:* This package is experimental.

![Autocomplete in user-defined types](http://staff.washington.edu/hansec/ac_fortran_ex1.gif)

![Go To Declaration](http://staff.washington.edu/hansec/ac_fortran_ex2.gif)

## Requirements
This package requires the following packages to be installed:
 * [autocomplete-plus](https://atom.io/packages/autocomplete-plus)
 * [language-fortran](https://atom.io/packages/language-fortran)

Additionally, you must have [Python](https://www.python.org/) installed on your system.

## Features
 * Provides suggestions across imported modules
 * Handles suggestions within user-defined types even when nested
 * Provides argument list for subroutine and function calls (optional arguments are indicated)
 * Provides return type for function calls
 * "Go To Declaration" support for FORTRAN object (including fields in user-defined types)

## Usage
Suggestions should be presented automatically while typing. At anytime you can force rebuilding of the index through the menu `Packages->Autocomplete FOTRAN->Rebuild Index`.

"Go To Declaration" is also supported for FORTRAN objects as the `FORTRAN-Goto Declaration` option in the context menu (right-click in editor). "Go To Declaration" can also be activated by the key binding `cmd-alt-g` on OS X and `ctrl-alt-g` on Linux/Windows.

### Notes
 * Initial setup of the index, including file parsing, is performed upon the first suggestion call. This may cause the first suggestion to take a moment to appear for large projects (usually <2 seconds).
 * After setup the index is dynamically updated as you modify files. However, if you edit a file outside of Atom changes will not be incorporated into the index until you edit that file in Atom or rebuild the index manually.
 * The grammar (fixed or free) is currently determined by file extension (`*.f` or `*.F` for fixed-form) and (`*.f90` or `*.F90` for free-form)
 * See TODO section.

## Configuration

### Setup module search paths
By default all files with the suffix `*.f`,`*.F`,`*.f90`, or `*.F90` in the base atom project directory are parsed
and used for generating suggestions. Specific folders containing FORTRAN source files can be set for
a given project by placing a JSON file (example below) named `.ac_fortran` in the base directory.
Folders to search are listed in the variable `mod_dirs` (relative to the project root) and excluded
files can be specified using the variable `excl_paths`. Directories are not added recursively, so
any nested sub directories must be explicitly listed.

    {
      "mod_dirs": ["subdir1", "subdir2"],
      "excl_paths": ["subdir1/file_to_skip.F90"]
    }

### Settings

![AC FORTRAN settings](http://staff.washington.edu/hansec/ac_fortran_settings.png)

The FORTRAN parser is written in Python so a Python implementation is required to use this package. The path to Python may be set in package settings.

## TODOs and current limitations
 * Inherited fields do not automatically update if fields are added/removed from a parent type
 * Provide dimension information
 * Handle explicit PASS statement for type bound procedures
