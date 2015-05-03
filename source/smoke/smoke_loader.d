module smoke.smoke_loader;

import std.algorithm;
import std.array;
import std.typecons;
import std.stdio;

import dstruct.weak_reference;

import smoke.smoke;
import smoke.smoke_util;
import smoke.string_util;

private extern(C++) class SmokeClassBinding : SmokeBinding {
    ClassLoader _loader;

    pure @safe nothrow
    this (ClassLoader loader) in {
        assert(loader !is null);
    } body {
        _loader = loader;
    }

    extern(C++) override void deleted(Smoke.Index classID, void* obj) {
        _loader.objectDeleted(obj);
    }

    extern(C++) override bool callMethod(Smoke.Index methodIndex, void* obj,
    void* args, bool isAbstract= false) body {
        Smoke.Method* method = _loader._smoke._methods + methodIndex;

        Smoke.StackItem[] argumentList = null;

        if (args) {
            argumentList = (cast(Smoke.StackItem*) args)[0 .. method.numArgs];
        }

        return _loader.methodCall(obj, method, argumentList, isAbstract);
    }

    extern(C++) override char* className(Smoke.Index classID) {
        return null;
    }

    extern(C++) override void __padding() {}
}

/**
 * This class represents a wrapper around SMOKE data for loading
 * and calling function pointers quickly for a given class.
 */
final class ClassLoader {
private:
    Smoke* _smoke;
    Smoke.Class* _cls;
    Smoke.Index _classIndex;
    SmokeClassBinding _binding;
    // We'll pack some methods in here, which may have many overloads.
    const(Smoke.Method*)[][string] _overloadedMethodMap;

    pure @safe nothrow
    this(Smoke* smoke, Smoke.Class* cls, Smoke.Index classIndex)
    in {
        assert(smoke !is null);
        assert(cls !is null);
    } body {
        _smoke = smoke;
        _cls = cls;
        _classIndex = classIndex;

        _binding = new SmokeClassBinding(this);
    }

    pure @safe nothrow
    void addMethod(string methodName, const(Smoke.Method*) method) {
        auto ptr = methodName in _overloadedMethodMap;

        if (ptr) {
            *ptr ~= method;
        } else {
            _overloadedMethodMap[methodName] = [method];
        }
    }

    pure @safe nothrow
    const(Smoke.Method*)[] methodMatches(string methodName) const {
        auto ptr = methodName in _overloadedMethodMap;

        return ptr !is null ? *ptr : null;
    }

    void objectDeleted(void* ptr) {
        Object object = cast(Object) loadSmokeMapping(ptr);

        if (object) {
            // Destroy the object early on our side if we have it.
            destroy(object);
        }

        // Remove the mapping, this may have already been done by the
        // class destructor before.
        deleteSmokeMapping(ptr);
    }

    bool methodCall(void* object, Smoke.Method* method,
    ref const(Smoke.StackItem[]) argumentList, bool isAbstract) {
        // TODO: Handle method calls here.

        return false;
    }
public:
    /**
     * Given another class loader and an object to cast, attempt to cast
     * the given object to an instance if the class identified by
     * otherLoader.
     */
    void* castTo(const(ClassLoader) otherLoader, void* object) const {
        if (otherLoader is this || object is null) {
            return object;
        }

        return otherLoader._smoke._castFn(
            object,
            _classIndex,
            otherLoader._classIndex
        );
    }

    /**
     * Call a constructor for a class with a method index and some
     * arguments.
     *
     * Returns: The pointer to the object which was constructed.
     */
    @trusted
    void* callConstructor(A...)(Smoke.Index methodIndex, A a) const {
        static if (A.length == 0) {
            // If we have a constructor of zero arguments, create a stack
            // with enough space for passing the binding.
            Smoke.StackItem[2] stack;
        } else {
            auto stack = createSmokeStack(a);
        }

        _cls.classFn(methodIndex, null, stack.ptr);

        // If calling a constructor, re-use the stack to pass the binding.
        stack[1].s_voidp = cast(void*) _binding;
        _cls.classFn(0, stack[0].s_voidp, stack.ptr);

        return stack[0].s_voidp;
    }

    /**
     * Call a method for a class with a method index and some arguments.
     *
     * Returns: A union type representing the return value.
     */
    @trusted
    Smoke.StackItem callMethod(A...)
    (Smoke.Index methodIndex, void* object, A a) const {
        auto stack = createSmokeStack(a);

        _cls.classFn(methodIndex, object, stack.ptr);

        return stack[0];
    }

    /**
     * Search for a method with a given name and list of argument types.
     * The types must be specified exactly as they are in C++.
     */
    @trusted pure nothrow
    immutable(Smoke.Index) findMethodIndex
    (string methodName, string[] argumentTypes ...) const {
        import std.c.string;

        methLoop: foreach(meth; methodMatches(methodName)) {
            if (meth.numArgs != argumentTypes.length) {
                continue;
            }

            // Slice the argument index list out.
            auto argIndexList = _smoke._argumentList[
                meth.args .. meth.args + meth.numArgs];

            foreach(i, argIndex; argIndexList) {
                // Skip to the type pointer.
                auto type = _smoke._types + argIndex;

                // FIXME: This is probably buggy, use a safer comparison
                // function.
                if (strcmp(argumentTypes[i].ptr, type.name)) {
                    continue methLoop;
                }
            }

            return meth.method;
        }

        return 0;
    }

    /**
     * Search for a method with a given name and list of argument types.
     * The types must be specified exactly as they are in C++.
     *
     * If the method cannot be found, throw an exception.
     */
    @trusted pure
    immutable(Smoke.Index) demandMethodIndex
    (string methodName, string[] argumentTypes ...) const {
        import std.exception;

        auto index = findMethodIndex(methodName, argumentTypes);

        enforce(
            index != 0,
            "Demanded method not found!"
            ~ "\nMethod was: " ~ methodName
        );

        return index;
    }
}

private WeakReference!(const(Object))[const(void*)] _weakMap;
private Object[const(void*)] _strongMap;

/**
 * Given a pointer to some C++ class and a D class,
 * store a mapping from the C++ class to a weak reference to the D class.
 *
 * This will make it possible to find the currently living D class wrapping
 * a C++ class so identity (x is y) can work, etc.
 *
 * This reference must be removed later by some means, say in a D class
 * destructor.
 */
@system nothrow
void storeSmokeMapping(const(void*) ptr, const(Object) object)
in {
    assert(ptr !is null, "null C++ class reference");
    assert(object !is null, "null D class reference");
    assert(ptr !in _weakMap, "Added pointer mapping twice!");
} body {
    _weakMap[ptr] = weak(object);
}

/**
 * Given a pointer to some C++ class, return the previously stored
 * reference to a D class wrapping the C++ class. If one is not stored,
 * return null.
 */
@system nothrow
const(Object) loadSmokeMapping(const(void*) ptr)
in {
    assert(ptr !is null, "null C++ class reference");
} body {
    if (auto weak = ptr in _weakMap) {
        return weak.get;
    }

    if (auto objPtr = ptr in _strongMap) {
        return *objPtr;
    }

    return null;
}

/**
 * Given a pointer to some C++ class, remove any weak or strong references
 * to the D class wrapping the C++ class.
 */
@system nothrow
void deleteSmokeMapping(const(void*) ptr)
in {
    assert(ptr !is null, "null C++ class reference");
} body {
    _weakMap.remove(ptr);
    _strongMap.remove(ptr);
}

/**
 * Given a pointer to a C++ class and a D class reference, store a strong
 * reference for that D class, such that it will not be collected until
 * the reference is cleared or the class is destroyed manually.
 */
@system nothrow
void storeStrongSmokeMapping(const(void*) ptr, const(Object) object)
in {
    assert(ptr !is null, "null C++ class reference");
    assert(object !is null, "null D class reference");
    assert(ptr !in _strongMap, "Added pointer mapping twice!");
} body {
    _strongMap[ptr] = cast(Object) object;
}

/**
 * This struct is used in generated SMOKE code for loading the smoke classes
 * and methods in the wrapper classes.
 */
struct SmokeLoader {
private:
    ClassLoader[string] _classMap;

    @trusted pure
    void loadClassMethodData(Smoke* smoke) {
        auto classList = smoke.classList;
        auto methNameList = smoke.methodNameList;

        // Copy out all of the class names up front, we'll need them.
        auto classNameList = classList
        .map!(x => x.className.toSlice.idup)
        .array;

        foreach(const ref meth; smoke.methodList) {
            // TODO: Filter fields and signals out? Are they in there?

            // Smoke "Methods" aren't *just* methods, they can be many things.
            if (meth.name >= methNameList.length
            || meth.classID >= classList.length) {
                continue;
            }

            // Reference our previous copy to get the class name as a string.
            string className = classNameList[meth.classID];

            if (className.length == 0) {
                continue;
            }

            ClassLoader classData;

            {
                auto ptr = className in _classMap;

                if (ptr) {
                    classData = *ptr;
                } else {
                    // Skip to the class pointer directly.
                    classData = new ClassLoader(
                        smoke,
                        smoke._classes + meth.classID,
                        meth.classID
                    );

                    // Save the class loader in the map for later.
                    _classMap[className] = classData;
                }
            }

            string methodName = methNameList[meth.name].toSlice.idup;

            classData.addMethod(methodName, &meth);
        }
    }

public:
    @trusted pure
    static immutable(SmokeLoader) create(Smoke*[] smokeList ...) {
        SmokeLoader loader;

        foreach(smoke; smokeList) {
            loader.loadClassMethodData(smoke);
        }

        return cast(immutable) loader;
    }

    // FIXME: Copying had to be enabled, as cast(immutable) was creating a copy.
    //@disable this(this);

    /**
     * Find a class by name, for loading its methods, etc.
     *
     * Params:
     * className = The class name.
     *
     * Returns: The class loader, or null if the class was not found.
     */
    pure @system nothrow
    immutable(ClassLoader) findClass(string className) const {
        auto ptr = className in _classMap;

        if (ptr is null) {
            return null;
        }

        return ptr !is null ? cast(immutable) *ptr : null;
    }

    /**
     * Find a class by name, and throw an exception if the class cannot
     * be loaded.
     *
     * Params:
     * className = The class name.
     *
     * Returns: The class loader.
     * Throws: An error if the class cannot be loaded.
     */
    pure @trusted
    immutable(ClassLoader) demandClass(string className) const {
        import std.exception;

        auto cls = findClass(className);

        enforce(
            cls !is null,
            "Demanded class not found!"
            ~ "\nClass was: " ~ className
        );

        return cls;
    }
}

/**
 * This is a base interface D classes wrapping C++ classes should implement.
 */
interface GeneratedSmokeWrapper {
    @system void disableGC();
}

/// A meaningless value used for skipping constructors in generated files.
enum Nothing : byte { nothing }

/// Some additional flags set for types generated with the smoke generator.
enum SmokeObjectFlags : uint {
    /// No flags set, the default value
    none = 0x0,
    /// This flag indicates that the object shouldn't be deleted by D.
    unmanaged = 0x1,
}
