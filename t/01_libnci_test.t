use v6;
use Test;
use NativeCall;

sub nci_dd (Num $in) returns Num is native('libnci_test') { ... }
ok 1;

is nci_dd(4), 8;
is nci_dd(-4.128), -8.256;

done;

# vim: ft=perl6 :
