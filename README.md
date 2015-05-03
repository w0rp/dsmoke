# DSMOKE

This is a library for using
[SMOKE](http://techbase.kde.org/Development/Languages/Smoke)
from D. This offers functionality for reading and interacting with SMOKE
libraries for executing C++ code through D and for generating D libraries from
generated SMOKE libraries.

## Quick Start

Check out the code somewhere, with the *dstruct* code in the same parent directory if you don't have it and use DUB to build the
library.

```
dub build
```

That's it. This library itself doesn't actually depend on SMOKE or any
SMOKE libraries itself. Libraries which link DSMOKE **will** have to link
the relevant SMOKE libraries they wish to use however, and likely the C++
standard library also.

## A Direct D Interface to SMOKE

This library contains a module ```smoke.smoke```, which provides an interface
to the SMOKE data as it is specified in C++. The C++ data structure is actually
a class composed entirely of C-compatible data types, and can thus be used
entirely from D by matching the layout of the data, which this module provides
as the type ``Smoke``.

The module also provides an ```extern(C++)``` interface to a ```SmokeBinding```
class, which is needed for handling virtual method calls and deletions in D
SMOKE wrapper libraries.

## Some Library Declarations Out of the Box

DSMOKE is pretty useless if there aren't any SMOKE libraries out there. DSMOKE
provides some function declarations for you out of the box so you can get
started quickly. At the moment this is limited to just the module
```smoke.smokeqt```, but there will be more to come.

## A Convenient, Less Confusing Data Structure

In addition to the direct access to SMOKE data, this library also provides a
data structure which can be used to get information about a SMOKE library in
the module ```smoke.smoke_container``` named ```SmokeContainer```. This data
structure is created by copying data out of the SMOKE library through the
```Smoke``` structures into a more convenient and easier to reason about form.

For example, you can get everything you need to know about QtCore and QtGUI
like so.

```D
// Link this file with smokebase, smokeqtcore, smokeqtgui, etc.

// Import the Smoke data structure
import smoke.smoke;
// Import declarations for smokeqt library functions.
import smoke.smokeqt;
// Import the container data structure.
import smoke.smoke_container;

immutable(SmokeContainer) loadQtSmokeContainer() {
    // Call the smokeqtcore library function to 'new' the Smoke data.
    init_qtcore_Smoke();
    // We can 'delete' it on scope exit, we copy everything we need safely.
    scope(exit) delete_qtcore_Smoke();
    // We want QtGUI stuff too.
    init_qtgui_Smoke();
    scope(exit) delete_qtgui_Smoke();

    // Create the immutable data structure using these two libraries.
    return SmokeContainer.create(qtcore_Smoke, qtgui_Smoke);
}

void main() {
    import std.stdio;

    // Now we've got everything we need to learn about the library,
    // to generate source files with, etc.
    auto container = loadQtSmokeContainer();

    // Let's write the name of every top level class in the libraries!
    foreach(cls; container.topLevelClassList) {
        writeln(cls.name);
    }
}
```

## A Reference D Code Generator, Too

The primary interest for using a library such as this is to make it possible to
generate D bindings to a C++ library. DSMOKE provides a ```SmokeGenerator```
object which can be used for this purpose in the module
```smoke.smoke_generator```, which interacts with the ```SmokeContainer```
object and lets you insert some configuration options and delegates for
tweaking the output.

```D
// Import this too so we can generate code.
import smoke.smoke_generator;

/* ... Write everything for creating a SmokeContainer as before ... */

void main() {
    // Get our data we used in the previous example.
    auto container = loadQtSmokeContainer();

    // Create the generator.
    // WARNING: API subject to change to eventually use the Builder pattern.
    auto generator = SmokeGenerator();

    /* ... Insert configuration options needed, and some WILL be needed ... */

    // Set a module name, which is required.
    generator.moduleName = "dqt";
    // Set the directory for pulling pre-defined files from, some are needed,
    // in particular for defining a SmokeLoader.
    generator.sourceDirectory = "dqt_predefined";

    // Write the output to a given directory.
    generator.writeToDirectory(container, "dqt");
}
```

Omitting some important details which will differ between different libraries.
the above example should be  a good starting point for using the
```SmokeGenerator``` to build your own D library.

## Try It Out, Comment, Contribute, destroy()

Probably missing a few things, that's about it. This library is available for
free under a two-clause BSD licence. so feel free to play with it, fork it,
submit pull requests for it, print out the source and shout at it, whatever you
want.
