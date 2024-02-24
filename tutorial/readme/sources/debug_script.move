script {
    use std::debug;
    fun debug_script(account: signer) {
        debug::print(&account);
        debug::print(&account);
    }
}