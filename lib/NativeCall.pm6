class OpaquePointer { }

class NativeArray {
    has $!unmanaged;
    has $!of;
    has $!max-index = -1;

    method postcircumfix:<[ ]>($idx) {
        if $idx > $!max-index {
            self!update-desc-to-index($idx);
        }
        Q:PIR {
            .local pmc bb
            .local string s
            $P0 = find_lex 'self'
            $P0 = getattribute $P0, '$!unmanaged'
            $P1 = find_lex '$idx'
            bb = new ['ByteBuffer']
            $S0 = $P0[$P1]
            bb = $S0
            s = bb.'get_string'('utf8')
            %r = box s
        };
    }

    method !update-desc-to-index($idx) {
        my $fpa = pir::new__Ps('ResizableIntegerArray');
        my $typeid;
        given $!of {
            when Str { $typeid = -70 }
            when Int { $typeid = -92 }
            when Num { $typeid = -83 }
            default { die "Unknown type"; }
        }
        Q:PIR {
            $P0 = find_lex '$fpa'
            $P1 = find_lex '$typeid'
            $P2 = find_lex '$idx'
            $I0 = $P2
            inc $I0
            $I1 = 0
            $I2 = $P1
          loop:
            if $I1 > $I0 goto loop_end
            push $P0, $I2
            push $P0, 1
            push $P0,  0
            inc $I1
            goto loop
          loop_end:
        };
        pir::assign__vPP(pir::descalarref__PP($!unmanaged), $fpa);
    }

    method Bool() {
        Q:PIR {
            $P0 = find_lex 'self'
            $P0 = getattribute $P0, '$!unmanaged'  # a Parrot UnManagedStruct
            $I0 = defined $P0
            %r = box $I0
        } ?? Bool::True !! Bool::False;
    }
}

our sub map-type-to-sig-char(Mu $type) {
    given $type {
        when Int           { 'i' }
        when Str           { 't' }
        when Num           { 'd' }
        when Rat           { 'd' }
        when OpaquePointer { 'p' }
        when Positional    { 'p' }
        default { die "Can not handle type " ~ $_.perl ~ " in an 'is native' signature." }
    }
}

our sub perl6-sig-to-backend-sig(Routine $r) {
    my $sig-string = $r.returns === Mu ?? 'v' !! map-type-to-sig-char($r.returns());
    my @params = $r.signature.params();
    for @params -> $p {
        $sig-string = $sig-string ~ map-type-to-sig-char($p.type);
    }
    return $sig-string;
}

our sub make-mapper(Mu $type) {
    given $type {
        when Positional {
            -> \$unmanaged-struct {
                NativeArray.new(unmanaged => $unmanaged-struct, of => $type.of)
            }
        }
        default { -> \$x { $x } }
    }
}

our multi trait_mod:<is>(Routine $r, $libname?, :$native!) {
    my $entry-point   = $r.name();
    my $call-sig      = perl6-sig-to-backend-sig($r);
    my $return-mapper = make-mapper($r.returns);
    my $lib;
    if $libname ne '' {
        $lib = pir::loadlib__Ps($libname);
        # $*ERR.say: "routine $r.name() signature $call-sig";
        unless $lib {
            die "The native library '$libname' required for '$entry-point' could not be located";
        }
    }
    pir::setattribute__vPsP($r, '$!do', -> |$c {
        my $func = pir::dlfunc__PPss(
            ($lib ?? pir::descalarref__PP($lib) !! pir::null__P()),
            $entry-point,
            $call-sig
        );
        $func // die("Could not locate symbol '$entry-point' in native library '{$libname || q<(resident)>}'");
        my $res;
        try {
            $res = $func.(|$c);
            CATCH { }
        };
        $return-mapper(pir::descalarref__PP($res));
    });
}

