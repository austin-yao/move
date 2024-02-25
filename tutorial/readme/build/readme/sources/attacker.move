address 0x69 {
    module victim {
        use std::debug;
        public fun incrementOnce(x: &mut u64) {
            *x = *x + 1;
            if (*x % 2 == 0) {
                printValueEven();
            } else {
                printValueOdd();
            }
        }

        public fun printValueEven() {
            let ans = 1;
            debug::print(&ans);
        }

        public fun printValueOdd() {
            let ans = 0;
            debug::print(&ans);
        }
    }

    module attacker {
        public fun incrementAttack() {
            let x = 0;
            0x69::victim::incrementOnce(&mut x);
        }

        public fun incrementReceive(x: &mut u64) {
            0x69::victim::incrementOnce(x);
        }
    }

    module attacker2 {
        public fun incrementAttack2(x: &mut u64) {
            0x69::attacker::incrementReceive(x);
        }
    }
}