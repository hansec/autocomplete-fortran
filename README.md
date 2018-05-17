# autocomplete-fortran package [![Package version](https://img.shields.io/apm/v/autocomplete-fortran.svg?style=flat-square)](https://atom.io/packages/autocomplete-fortran) [![Plugin installs](https://img.shields.io/apm/dm/autocomplete-fortran.svg?style=flat-square)](https://atom.io/packages/autocomplete-fortran)

## Warning: this package is now deprecated

This package is no longer being updated. It has been replaced by the [ide-fortran](https://atom.io/packages/ide-fortran) package, which has improved functionality via common [IDE support in Atom](https://ide.atom.io/).

## Description

This package provides autocomplete suggestions and "Go To Declaration" support for FORTRAN code using [autocomplete-plus](https://atom.io/packages/autocomplete-plus).

*Note:* This package is experimental. If you find any bugs or if there are any missing features you would like please open an [issue](https://github.com/hansec/autocomplete-fortran/issues).

![Autocomplete in user-defined types](http://staff.washington.edu/hansec/ac_fortran_ex1.gif)

![Go To Declaration](http://staff.washington.edu/hansec/ac_fortran_ex2.gif)

## Requirements
This package requires the following packages to be installed:
 * [autocomplete-plus](https://atom.io/packages/autocomplete-plus)
 * [language-fortran](https://atom.io/packages/language-fortran)

Additionally, you must have [Python](https://www.python.org/) installed on your system.

This package has been tested and *should* work on :apple: Mac OSX, :penguin: Linux and Windows

## Features
 * Provides suggestions across imported modules
 * Provides suggestions within user-defined types even when nested
 * Provides argument list for subroutine and function calls (optional arguments are indicated)
 * Indicates return type for function calls
 * "Go To Declaration" support for FORTRAN objects (including fields in user-defined types)
 * Support for generating and using external index files (completion for libraries outside project ex. MPI, BLAS/LAPACK, etc.)

## Usage
Suggestions should be presented automatically while typing. At anytime you can force rebuilding of the index through the menu `Packages->Autocomplete FOTRAN->Rebuild index`.

"Go To Declaration" is also supported for FORTRAN objects as the `FORTRAN-Goto Declaration` option in the context menu (right-click in editor). "Go To Declaration" can also be activated by the key binding `cmd-alt-g` on OS X and `ctrl-alt-g` on Linux/Windows.

### Notes
 * Initial setup of the index, including file parsing, is performed upon the first suggestion call. This may cause the first suggestion to take a moment to appear for very large projects (this is usually not noticeable).
 * After setup the index is dynamically updated as you modify files. However, if you edit a file outside of Atom (ex. switching branches in git,svn,etc.) changes will not be incorporated into the index until you edit the modified files in Atom or rebuild the index manually.
 * The grammar (fixed or free) is currently determined by file extension (`f,F,f77,F77,for,FOR,fpp,FPP` for fixed-form) and (`f90,F90,f95,F95,f03,F03,f08,F08` for free-form)

## Configuration

### Setup module search paths
By default all files with the suffix `f,F,f77,F77,for,FOR,fpp,FPP` or `f90,F90,f95,F95,f03,F03,f08,F08` in the
base atom project directory are parsed and used for generating suggestions. Specific folders containing FORTRAN
source files can be set for a given project by placing a JSON file (example below) named `.ac_fortran` in the
base directory. Folders to search are listed in the variable `mod_dirs` (relative to the project root) and excluded
files can be specified using the variable `excl_paths`. Directories are not added recursively, so
any nested sub directories must be explicitly listed.

    {
      "mod_dirs": ["subdir1", "subdir2"],
      "excl_paths": ["subdir1/file_to_skip.F90"]
    }

### External index files
Additional autocompletion information can also be imported for use in the current project by specifying index files
in the variable `ext_index` (relative to the project root) in your project's `.ac_fortran` file. Index files can be
generated from a project through the menu through the menu `Packages->Autocomplete FOTRAN->Save external index file`.
This action will save a file called `ac_fortran_index.json` in the root directory of the project containing all the
information necessary to provide autocompletion for FORTRAN entities in the project. However, source file information
will be stripped so "Go To Declaration" will not be available for externally imported entities. This file can then
be used to make these entities available in a different project. Some useful index files for common libraries
(ex. BLAS/LAPACK) are available at https://github.com/hansec/autocomplete-fortran-ext.

    {
      "ext_index": ["blas_index.json"]
    }

### Settings

The FORTRAN parser is written in Python so a Python implementation is required to use this package. The path to Python may be set in package settings (required for Windows).

Many additional settings, such as the selection keys (`TAB`/`ENTER`), are governed by the global settings for the [autocomplete-plus](https://atom.io/packages/autocomplete-plus) package.

## TODOs
 * Handle explicit PASS statement for type bound procedures
 * Allow fuzzy completion suggestions

--------

If you *really* like [autocomplete-fortran](https://atom.io/packages/autocomplete-fortran) you can <a href='https://paypal.me/hansec' target="_blank">buy me a :coffee: or a :beer:</a> to say thanks.
