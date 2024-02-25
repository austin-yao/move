module 0x2::Test {
    use std::signer;
    use std::debug;

    struct Resource has key {i : u64}
    struct Foo { x: u64, y: bool}
    struct Bar {foo : Foo}
    struct Baz {}

    public fun publish(account: &signer) {
        move_to(account, Resource{i:10});
    }

    public fun write(account: &signer, i:u64) acquires Resource {
        borrow_global_mut<Resource>(signer::address_of(account)).i = i;
    }

    public fun unpublish(account: &signer) acquires Resource {
        let Resource {i: _} = move_from(signer::address_of(account));
    }

    public fun test() {
        let x = 1;
        debug::print(&x);
        let y = move x + 1;
        debug::print(&y);
        let z = move y + 2; 
        debug::print(&z);
        // unlike other languages, let is not used to assign a constant
        // use const to assign a constant
        // const <name>: <type> = <expression>;
        let z = z + 1;
        debug::print(&z);
    }

    // uncomment and run move build to see the error
    // public fun testStructDanglingRefError() {
    //     let foo = Foo {x: 3, y: false};
    //     let Foo {x, y } = &foo;
    //     debug::print(&foo);
    //     debug::print(x);
    //     debug::print(y);
    //     foo.x = 1;
    //     debug::print(x);
    //     let Foo {x: x1, y: foo_y} = foo;
    // }

    // public fun copying_resource() {
    //     let foo = Foo { x: 100, y: false };
    //     let foo_copy = copy foo; // error! 'copy'-ing requires the 'copy' ability
    //     let foo_ref = &foo;
    //     let another_copy = *foo_ref // error! dereference requires the 'copy' ability
    // }

    public fun testStruct() {

    }
}