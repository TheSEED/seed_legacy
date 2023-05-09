
#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

###########################################################
#
#    This function retrims sequences by removing them one at a time and retrimming the 
#    result of re-inserting them back in
# retrim_seqs(  seqs => UntrimmedSeqs, 
#               ali  => TrimmedAlignmentToImprove,
# 	        trimmed => TrimmedSequences
#            )
# 
#    This gives you a set of trimmed sequences that can be used as a "kernel"
# kernel_of_trimmed_seqs(   seqs          => Seqs ToTrim,
# 	                    min_iden_diff => ParameterThatDetrminesGroupSizes,
# 	                    min_hits      => Minimum Fraction of Sequences nedded in First/Last Trimmed Col
# 	                    min_inf       => Minimum "information content" for trimming boundary
# 
# 
#    This gives an alignment of the trimmed sequences (uses kernel_of_trimmed_sequences and aligns the
#    resulting set).
# trimmed_aligned_kernel(   seqs          => Seqs ToTrim,
# 	                    min_iden_diff => ParameterThatDetrminesGroupSizes,
# 	                    min_hits      => Minimum Fraction of Sequences nedded in First/Last Trimmed Col
# 	                    min_inf       => Minimum "information content" for trimming boundary
# 
###########################################################

package PHOB;

use strict;
use gjoseqlib;
use representative_sequences;
use Data::Dumper;
use Carp;
use gjoalignment;
use gjoparseblast;

sub retrim_seqs {
    my(%args) = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
    my($tmp_dir,$save_tmp_dir) = &temporary_directory(\%args);

    my($seqs)          = $args{seqs}          || return undef;
    my($trimmed)       = $args{trimmed};      
    my($ali)           = $args{ali};

    if ($trimmed && (! $ali))
    {
	$ali = &align_seqs({ seqs => $trimmed, tmpdir => $tmp_dir });
    }

    my $retrimmed = [];
    my $n = @$ali;

    my($i,$j,$k);
    for ($i=0; ($i < $n); $i++)
    {
	my $copy = [];
	foreach my $tuple (@$ali)
	{
	    push(@$copy,[@$tuple]);
	}
	my $one_seq = splice(@$copy,$i,1);
#	print STDERR &Dumper(['one seq',$one_seq,$copy]);
	for ($j=0; ($j < @$seqs) && ($seqs->[$j]->[0] ne $one_seq->[0]); $j++) {}
	my $new_ali = &gjoalignment::add_to_alignment($seqs->[$j], $copy, 1);
	for ($k=0; ($k < @$new_ali) && ($new_ali->[$k]->[0] ne $one_seq->[0]); $k++) {}
	if ($k < @$new_ali)
	{
	    my($id,$desc,$oldseq) = @$one_seq;
	    my $packed_old = &gjoseqlib::pack_seq($oldseq);
	    my $packed_new = &gjoseqlib::pack_seq($new_ali->[$k]->[2]);
	    if ($packed_old ne $packed_new)
	    {
#	        print STDERR "retrimmed\n\t$packed_old\nto\t$packed_new\n\n";
	    }
	    push(@$retrimmed,[$id,$desc,$packed_new]);
	}
	else
	{
	    die "lost $one_seq->[0]";
	}
    }
    if (! $save_tmp_dir) { system "/bin/rm -r $tmp_dir" }
    return $retrimmed;
}

sub align_to_seq {
    my($ref) = @_;

    my($id,$desc,$ali_seq) = @$ref;
    return [$id,$desc,&gjoseqlib::pack_seq($ali_seq)];
}

sub kernel_of_trimmed_seqs {
    my(%args) = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
    my($tmp_dir,$save_tmp_dir) = &temporary_directory(\%args);

    my($seqs)          = $args{seqs}          || return undef;
    my($min_iden_diff) = $args{min_iden_diff} || 0.8;
    my($min_hits)      = $args{min_hits}      || 0.7;      # min fraction of seqs in column
    my($min_inf)       = $args{min_inf}       || 2;        # minimum information content in column;
    my($retrim)        = $args{retrim};

    my @sorted_seqs = sort { length($b->[2]) <=> length($a->[2]) } @$seqs;
    my($reps,undef) = &representative_sequences::rep_seq_2(\@sorted_seqs,{ max_sim => $min_iden_diff });
    if (! ($reps && (@$reps > 1))) { $reps = $seqs }

 #  foreach $_ (@$reps) { print STDERR "$_->[0], ",length($_->[2]),"\n"; }

    my($i,%trimming_data,$trimming_tuples);
    for ($i=0; ($i < @$reps) && ($i < 5); $i++)
    {
	my $long_seq = [$reps->[$i]];
	$trimming_tuples = &get_estimates_based_on_one_seq($long_seq,$reps,$tmp_dir,$min_hits,$min_inf);
	foreach my $rep_id (keys(%$trimming_tuples))
	{
	    push(@{$trimming_data{$rep_id}},$trimming_tuples->{$rep_id});
	}
    }
    $trimming_tuples = &condense_tuples(\%trimming_data);

    my($seqs_in_kernel)  = &trimmed_seqs($trimming_tuples,$reps);

    if ($retrim)
    {
#	print STDERR &Dumper($seqs_in_kernel);
	$seqs_in_kernel  = &retrim_seqs( trimmed => $seqs_in_kernel,
					 seqs    => $seqs);
#	print STDERR &Dumper($seqs_in_kernel); 
    }
    if (! $save_tmp_dir) { system "/bin/rm -r $tmp_dir" }
    return $seqs_in_kernel;
}

sub trim_alignment {
    my(%args) = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
    my($tmp_dir,$save_tmp_dir) = &temporary_directory(\%args);

    my($ali)           = $args{ali}           || return undef;
    my($min_hits)      = $args{min_hits}      || 0.7;      # min fraction of seqs in column
    my($min_inf)       = $args{min_inf}       || 2;        # minimum information content in column;

    (@$ali > 0) || return undef;
    my $len_of_ali_seq = length($ali->[0]->[2]);

    my $tot_all = 0;
    my @aa = qw(A C D E F G H I K L M N P Q R S T V W Y);
    my %aa = map { $_ => 1 } @aa;
    my $all_seq = join('',map { uc $_->[2] } @$ali);

    my %aa_cnt = map { $_ => ($all_seq =~ s/$_//g) } @aa;

    foreach my $c (@aa)
    {
	$tot_all += $aa_cnt{$c};
    }
    my %aa_freq = map { $_ => $aa_cnt{$_} / $tot_all } @aa;

    my($i);
    for ($i=0; ($i < $len_of_ali_seq) && (! &good_enough($ali,$i,\%aa_freq,$min_hits,$min_inf)); $i++) {}
    my $start = ($i < $len_of_ali_seq) ? $i : undef;
    if (! $start) { return undef }

    for ($i=$len_of_ali_seq-1; ($i >= 0) && (! &good_enough($ali,$i,\%aa_freq,$min_hits,$min_inf)); $i--) {}
    my $new_len = $i+1 - $start;
    my @new_ali = map { [$_->[0],$_->[1],substr($_->[2],$start,$new_len)] } @$ali;
    return \@new_ali;
}

sub good_enough {
    my($ali,$col,$aa_freq,$min_hits,$min_inf) = @_;

    my(%counts,$x);
    foreach $x (@$ali)
    {
	$counts{uc substr($x->[2],$col,1)}++;
    }

    my $nseqs = @$ali;
    my $minN = $min_hits * $nseqs;

    my $infoI = 0;
    my $N = 0;

    my($c);
    foreach $c (grep { $aa_freq->{$_} } keys(%counts))
    {
	$N += $counts{$c};
    }
	    
    if ($N < $minN) { return 0 }

    foreach $c (grep { $aa_freq->{$_} }keys(%counts))
    {
	my $n = $counts{$c};
	my $g = ($n + $aa_freq->{$c}) / ($N + 1);
	$infoI += $g * log($g/$aa_freq->{$c});
    }
    $infoI /= log(2);
    return $infoI < $min_inf;
}

sub condense_tuples {
    my($trimming_data) = @_;

    my $trimming_tuples = {};
    foreach my $rep_id (keys(%$trimming_data))
    {
	my $x = $trimming_data->{$rep_id};
	my($best_start,$best_end);

	my @starts = map { $_->[0] } grep { ! $_->[1] } @$x;
	if (@starts > 0)
	{
	    $best_start = &pick1(\@starts);
	}
	else
	{
	    @starts = map { $_->[0] } @$x;
	    if (@starts > 0)
	    {
		$best_start = &pick1(\@starts);
	    }
	}

	my @ends = map { $_->[2] } grep { ! $_->[3] } @$x;
	if (@ends > 0)
	{
	    $best_end = &pick1(\@ends);
	}
	else
	{
	    @ends = map { $_->[2] } @$x;
	    if (@ends > 0)
	    {
		$best_end = &pick1(\@ends);
	    }
	}
	$trimming_tuples->{$rep_id} = [$best_start,$best_end];
    }
    return $trimming_tuples;
}

sub pick1 {
    my($xL) = @_;

    my @values = sort { $a <=> $b } @$xL;
    return $values[int(@values/2)];
}

sub get_estimates_based_on_one_seq {
    my($longest,$reps,$tmp_dir,$min_hits,$min_inf) = @_;

    &gjoseqlib::print_alignment_as_fasta("$tmp_dir/longest",$longest);
    &gjoseqlib::print_alignment_as_fasta("$tmp_dir/reps",$reps);
    &run("formatdb -i $tmp_dir/reps -pT");
    open(BLAST,"blastall -i $tmp_dir/longest -d $tmp_dir/reps -p blastp -FF -b 10000 -v 10000 -e 1.0e-5 |")
	|| die "could not blast using blastall -i $tmp_dir/longest -d $tmp_dir/reps -p blastp -FF -b 10000 -v 10000";
    my(@counts,$i,%saved_hsps);
    while (my $db_seq_out = &gjoparseblast::next_blast_subject(\*BLAST,1))
    {
	my $subject_id = $db_seq_out->[3];
	my $hsps       = &remove_overlapping_hsps($db_seq_out->[6]);

	$saved_hsps{$subject_id} = $hsps;

	foreach my $hsp (@$hsps)
	{
	    my($qb,$qe,$qseq,$sb,$se,$sseq) = @$hsp[9..14];
	    my $qpos = $qb;
	    for ($i=0; ($i < length($qseq)); $i++)
	    {
		if (substr($qseq,$i,1) ne "-")
		{
		    my $c = uc substr($sseq,$i,1);
		    $counts[$qpos]->{$c}++;
		    $qpos++;
		}
	    }
	}
    }
    close(BLAST);

    my($start_largest,$end_largest) = &extract_start_end(\@counts,scalar @$reps,$min_hits,$min_inf);
    my($trimming_tuples)            = &extract_all_positions($start_largest,$end_largest,\%saved_hsps);
    return $trimming_tuples;
}

sub trimmed_aligned_kernel {
    my(%args) = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
    my($tmp_dir,$save_tmp_dir) = &temporary_directory(\%args);

    my($seqs)          = $args{seqs}          || return undef;
    my($retrim)        = $args{retrim} ? 1 : 0;

    my($trimmed)       = &kernel_of_trimmed_seqs(seqs => $seqs, retrim => $retrim);

    my($ali)           = &align_seqs(seqs => $trimmed,
				     tmpdir => $tmp_dir
				    );
    if (! $save_tmp_dir) { system "/bin/rm -r $tmp_dir" }
    return $ali;
}

sub trimmed_seqs {
    my($trimming_tuples,$reps) = @_;
    
    my $trimmed = [];
    foreach my $rep (@$reps)
    {
	my($id,$desc,$seq) = @$rep;
	if (my $x = $trimming_tuples->{$id})
	{
	    my($start,$end) = @$x;
	    if ($start && $end)
	    {
		my $start = &max(1,$start);
		my $end   = &min(length($seq),$end);
		push(@$trimmed,[$id,$desc,substr($seq,$start-1,($end+1-$start))]);
	    }
	}
    }
    return $trimmed;
}

sub extract_start_end {
    my($counts,$nseqs,$min_hits,$min_inf) = @_;
    my($i,%tot,$x,$c,$start,$end);

    for ($i=0; ($i < @$counts); $i++)
    {
	if (defined($x = $counts->[$i]))
	{
	    foreach $c (keys(%$x))
	    {
		$tot{$c} += $x->{$c};
	    }
	}
    }


    my $tot_all = 0;
    my @aa = qw(A C D E F G H I K L M N P Q R S T V W Y);
    my %aa = map { $_ => 1 } @aa;

    foreach $c (@aa)
    {
	$tot_all += $tot{$c};
    }

    my %p;
    foreach $c (@aa)
    {
	$p{$c} = $tot{$c} / $tot_all;
    }

    my $minN = $min_hits * $nseqs;

    my @info;
    for ($i=0; ($i < @$counts); $i++)
    {
	my $infoI = 0;
	if (defined($x = $counts->[$i]))
	{
	    my $N = 0;
	    foreach $c (grep { $aa{$_} } keys(%$x))
	    {
		$N += $x->{$c};
	    }
	    
	    if ($N >= $minN)
	    {
		foreach $c (grep { $aa{$_} }keys(%$x))
		{
		    my $n = $x->{$c};
		    my $g = ($n + $p{$c}) / ($N + 1);
		    $infoI += $g * log($g/$p{$c});
		}
		$infoI /= log(2);
	    }
	}
	$info[$i] = $infoI;
#	print STDERR "info[$i] = $infoI\n";
    }

    for ($start=0; ($start < @info) && ($info[$start] < $min_inf); $start++) {}
    for ($end = @info - 1; ($end >= 0) && ($info[$end] < $min_inf); $end--) {}
    return ($start < $end) ? ($start,$end) : undef;
}

sub extract_all_positions {
    my($start_largest,$end_largest,$hspH) = @_;
    my($subject_id);

    my $trimming_tuples = {};
    foreach $subject_id (keys(%$hspH))
    {
	my($start,$end,$hsp);
	my($start_guess,$start_howfar);
	my($end_guess,$end_howfar);
	my $hsps = $hspH->{$subject_id};
	foreach $hsp (@$hsps)
	{
	    if (! defined($start))
	    {
		if (&between($hsp->[9],$start_largest,$hsp->[10]))
		{
		    $start = &find_match_in_hsp($hsp,$start_largest,'start');
		    if ($start < 0) { confess "negative start" }
		}
		else
		{
		    my($guess,$howfar) = &guess($hsp,$start_largest,"start");
		    if ((! defined($start_guess)) || ($howfar < $start_howfar))
		    {
			($start_guess,$start_howfar) = ($guess,$howfar);
		    }
		}
	    }

	    if (! defined($end))
	    {
		if (&between($hsp->[9],$end_largest,$hsp->[10]))
		{
		    $end = &find_match_in_hsp($hsp,$end_largest,'end');
		}
		else
		{
		    my($guess,$howfar) = &guess($hsp,$end_largest,"end");
		    if ((! defined($end_guess)) || ($howfar < $end_howfar))
		    {
			($end_guess,$end_howfar) = ($guess,$howfar);
		    }
		}
	    }
	}

	my($extrapolated_start,$extrapolated_end) = (0,0);
	if ((! $start)  && $start_guess && ($start_howfar <= 25))
	{ 
	    $start = $start_guess ;
	    $extrapolated_start = 1;
	}
	if ((! $end)    && $end_guess && ($end_howfar <= 25))
	{ 
	    $end   = $end_guess ;
	    $extrapolated_end = 1;
	}
	$trimming_tuples->{$subject_id} =[$start,$extrapolated_start,$end,$extrapolated_end];
    }
    return $trimming_tuples;
}

sub guess {
    my($hsp,$goal,$dir) = @_;
    my $qpos = $hsp->[9];
    my $qend = $hsp->[10];
    my $qseq = $hsp->[11];
    my $spos = $hsp->[12];
    my $send = $hsp->[13];
    my $sseq = $hsp->[14];
    my $ln   = length($qseq);

    if (($dir eq 'start') && ($qpos > $goal))
    {
	my $howfar = $qpos - $goal;
	return ($spos - $howfar, $howfar);
    }

    elsif (($dir eq 'end') && ($qend < $goal))
    {
	my $howfar = $goal - $qend;
	return ($send + $howfar, $howfar);
    }
    return undef;
}

sub find_match_in_hsp {
    my($hsp,$goal,$dir) = @_;

    my $qpos = $hsp->[9];
    my $qseq = $hsp->[11];
    my $spos = $hsp->[12];
    my $sseq = $hsp->[14];
    my $ln   = length($qseq);
    my $i = 0;
    while ($i < $ln)
    {
	if (substr($qseq,$i,1) eq '-')
	{
	    $spos++;
	}
	elsif ($qpos == $goal)
	{
	    if (substr($sseq,$i,1) eq "-")
	    {
		return ($dir eq "start") ? $spos+1 : $spos;
	    }
	    else
	    {
		return $spos;
	    }
	}
	else
	{
	    if (substr($sseq,$i,1) ne "-") { $spos++ }
	    $qpos++;
	}
	$i++;
    }
    return undef;
}

sub remove_overlapping_hsps {
    my($hsps) = @_;

    return &remove_ov1(&remove_ov1($hsps,9),12);
}

sub remove_ov1 {
    my($hsps,$off) = @_;

    my @hsps_tuples = map { [$_,$_->[$off],$_->[$off+1]] } @$hsps;
    my $hsps1 = [];

    foreach my $hsp (@hsps_tuples)
    {
	my $i;
	for ($i=0; ($i < @$hsps1) && &no_overlap($hsps1->[$i],$hsp); $i++) {}
        if ($i == @$hsps1)
	{
	    push(@$hsps1,$hsp);
	}
    }
    return [map { $_->[0] } @$hsps1];
}

sub no_overlap {
    my($hsp1,$hsp2) = @_;
    my($b1,$e1) = @$hsp1;
    my($b2,$e2) = @$hsp2;

    my $min_ln = &min($e1-$b1,$e2-$b2) + 1;
    my $ov;
    if   (&between($b1,$b2,$e1))
    {
	$ov = &min($e1,$e2) - $b2;
    }
    elsif (&between($b2,$b1,$e2))
    {
	$ov = &min($e1,$e2) - $b1;
    }
    else
    {
	$ov = 0;
    }
    return ($ov < (0.2 * $min_ln));
}

sub align_seqs {
    my(%args) = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
    
    my($seqs)          = $args{seqs}          || return undef;
    my($tmp_dir,$save_tmp_dir) = &temporary_directory(\%args);

    my $seqfile                = "$tmp_dir/align_fasta_tmp_$$.fasta";
    my $outfile                = "$tmp_dir/align_fasta_tmp_$$.ali";

    my ( $id, $def, $seq, $id2, %desc, @seqs2 );

    $id2 = "seq00000";
    @seqs2 = map { ( $id, $def, $seq ) = @$_;
		   $desc{ ++$id2 } = [ $id, $def ];
		   [ $id2, "", $seq ]
		   } @$seqs;

    gjoseqlib::print_alignment_as_fasta( $seqfile, \@seqs2 );
    &run("$FIG_Config::ext_bin/muscle < $seqfile > $outfile 2> /dev/null");
    my @aligned = gjoseqlib::read_fasta( $outfile );
    if (! $save_tmp_dir) { system "/bin/rm -r $tmp_dir" }
    return [map { [ @{ $desc{$_->[0]} }, $_->[2] ] } @aligned];
}


# This routine was written by Gary to definitively handle the "scratch" subdirectory issue.
# It takes as parameters key-value pairs.  The relevant ones are
# 
#     tmpdir => NameOfTmpDirectoryToBeUsed  [can be ommitted]
#     tmp    => TheNameOfTheTmpDirectoryToContainTheSubdirectory [can be ommitted]
# 
# if tmpdir exists, save_tmp is set to "true".  You need to test this at the end
# of your script and blow away the directory unless save_tmp is true.
# if tmpdir does not exist, it will be created if possible.
# 
# tmp is where to put tmpdir, if it is not specified.  if tmp is omitted, it
# will all be ok.
# 
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#  ( $tmp_dir, $save_tmp ) = temporary_directory( \%options )
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub temporary_directory
{
    my $options = shift;

    my $tmp_dir  = $options->{ tmpdir };
    my $save_tmp = $options->{ savetmp } || '';

    if ( $tmp_dir )
    {
        if ( -d $tmp_dir ) { $options->{ savetmp } = $save_tmp = 1 }
    }
    else
    {
        my $tmp = $options->{ tmp } && -d  $options->{ tmp } ?  $options->{ tmp }
                : $FIG_Config::temp && -d  $FIG_Config::temp ?  $FIG_Config::temp
                :                      -d '/tmp'             ? '/tmp'
                :                                              '.';
	$tmp_dir = sprintf( "$tmp/fig_tmp_dir.%05d.%09d", $$, int(1000000000*rand) );
    }

    if ( $tmp_dir && ! -d $tmp_dir )
    {
        mkdir $tmp_dir;
        if ( ! -d $tmp_dir )
        {
            print STDERR "temporary_directory could not create '$tmp_dir: $!'\n";
            $options->{ tmpdir } = $tmp_dir = undef;
        }
    }

    return ( $tmp_dir, $save_tmp );
}

sub run {
    my($cmd) = @_;
    (system($cmd) == 0) || confess("FAILED: $cmd");
}

sub between {
    my($x,$y,$z) = @_;
    return (($x <= $y) && ($y <= $z));
}

sub min {
    my($x,$y) = @_;
    return ($x < $y) ? $x : $y;
}

sub max {
    my($x,$y) = @_;
    return ($x < $y) ? $y : $x;
}


sub alignable_subsets {
    my(%args) = (ref($_[0]) eq 'HASH') ? %{$_[0]} : @_;
    
    my($seqs)          = $args{seqs}          || return undef;
    my($max_sim)       = $args{max_sim} || 0.25;

    if (@$seqs < 2) { return (); }

    my %to_tuple = map { $_->[0] => $_ } @$seqs;
    my @sorted_seqs = sort { length($b->[2]) <=> length($a->[2]) } @$seqs;
    my($reps,$representing) = &representative_sequences::rep_seq_2(\@sorted_seqs,{ max_sim => $max_sim });

    my @sets = ();
    foreach my $rep (sort { length($b->[2]) <=> length($a->[2]) } @$reps)
    {
	my $others;
	if (($others = $representing->{$rep->[0]}) && (@$others > 0))
	{
	    push(@sets,[$rep,map { $to_tuple{$_} } @$others]);
	}
    }
    return @sets;
}

1;
