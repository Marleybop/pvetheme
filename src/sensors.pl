        # marleybop-pvetheme sensors
        # Temperatures and fan speeds for the node Summary, read straight from the kernel's
        # hwmon files (no lm-sensors needed). Added by "pvetheme sensors on"; remove with "off".
        $res->{'marleybop-sensors'} = eval {
            my $first = sub { open(my $fh, '<', $_[0]) or return undef; my $l = <$fh>; close($fh); return undef if !defined($l); chomp $l; return $l; };
            my @out;
            for my $dir (sort glob('/sys/class/hwmon/hwmon*')) {
                my $chip = $first->("$dir/name") // next;
                for my $in (sort glob("$dir/temp*_input"), sort glob("$dir/fan*_input")) {
                    my $val = $first->($in);
                    next if !defined($val) || $val !~ /^-?\d+$/;
                    (my $base = $in) =~ s/_input$//;
                    my ($kind, $idx) = $base =~ m!/(temp|fan)(\d+)$! or next;
                    my $entry = {
                        chip => $chip, kind => $kind, index => int($idx),
                        label => $first->("${base}_label") // '',
                        value => $kind eq 'temp' ? $val / 1000 : int($val),
                    };
                    if ($kind eq 'temp') {
                        for my $lim (qw(max crit)) {
                            my $l = $first->("${base}_$lim");
                            $entry->{$lim} = $l / 1000 if defined($l) && $l =~ /^-?\d+$/;
                        }
                    }
                    push @out, $entry;
                    last if @out >= 64;
                }
            }
            \@out;
        } // [];
        # marleybop-pvetheme sensors END
