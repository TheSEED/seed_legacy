#
# Copyright (c) 2003-2013 University of Chicago and Fellowship
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

### start

use FIG;
use FIG_CGI;
my $have_fcgi;
eval {
    require CGI::Fast;
    $have_fcgi = 1;
};


use strict;
use FIGjs;           #  toolTipScript
use GenoGraphics;    #  render
use gjoparseblast;   #  next_blast_hsp
use BlastInterface;  #  blast, verify_db
use GenomeSelector;
use Tracer;

use URI::Escape;     #  uri_escape
use POSIX;
use Digest::MD5;     #  md5_hex
use HTML;

my $have_sphinx;
my $sphinx_search_mode;
BEGIN {
    eval {
        require Sphinx::Search;
        #
        # Assign this up here where we know the symbol is available.
        #
        $sphinx_search_mode = &Sphinx::Search::SPH_MATCH_EXTENDED();
        $have_sphinx++;
        require SeedSearch;
    };
}

my $this_script = "index.cgi";

our $done;
sub done
{
    &$done;
}

if ($have_fcgi && $ENV{REQUEST_METHOD} eq '')
{
    {
        package AllDone;
        sub new
        {
            my($class) = @_;
            return bless {}, $class;
        }
    }
    $done = sub { die AllDone->new;   };

    my $max_requests = $FIG_Config::fcgi_max_requests || 50;
    my $n_requests = 0;

    my $fig = new FIG;

    warn "begin loop\n";
    while (($max_requests == 0 || $n_requests++ < $max_requests) &&
           (my $cgi = new CGI::Fast()))
    {
        my $user = $cgi->param('user') || "";

        warn "have request\n";
        eval {
            &page_run($fig, $cgi, $user);
        };
        warn "Done\n";
        if ($@)
        {
            if (ref($@) eq 'AllDone')
            {
                next;
            }
            warn "code died, cgi=$cgi returning error\n";
            print $cgi->header(-status => '500 error in body of cgi processing');
            print $@;
        }
    }
}
else
{
    $done = sub { exit 0; };
    my($fig, $cgi, $user);

    eval {
        ($fig, $cgi, $user) = FIG_CGI::init(debug_save => 0,
                                            debug_load => 0,
                                            print_params => 0);
    };

    if ($@ ne "")
    {
        my $err = $@;

        my(@html);

        push(@html, $cgi->p("Error connecting to SEED database."));
        if ($err =~ /Could not connect to DBI:.*could not connect to server/)
        {
            push(@html, $cgi->p("Could not connect to relational database of type $FIG_Config::dbms named $FIG_Config::db on port $FIG_Config::dbport."));
        }
        else
        {
            push(@html, $cgi->pre($err));
        }
        &HTML::show_page($cgi, \@html, 1);
        exit;
    }
    &page_run($fig, $cgi, $user);
}
exit 0;

sub page_run
{
    my($fig, $cgi, $user) = @_;

    Trace("Connected to FIG.") if T(2);
    my($map,@orgs,$user,$map,$org,$made_by,$from_func,$to_func);

    #for my $k (sort keys %ENV)
    #{
    #    warn "$k=$ENV{$k}\n";
    #}

    $ENV{"PATH"} = "$FIG_Config::bin:$FIG_Config::ext_bin:" . $ENV{"PATH"};

    if (0)
    {
        my $VAR1;
        eval(join("",`cat /tmp/index_parms`));
        $cgi = $VAR1;
        #   print STDERR &Dumper($cgi);
    }

    if (0)
    {
        print $cgi->header;
        my @params = $cgi->param;
        print "<pre>\n";
        foreach $_ (@params)
        {
            print "$_\t:",join(",",$cgi->param($_)),":\n";
        }

        if (0)
        {
            if (open(TMP,">/tmp/index_parms"))
            {
                print TMP &Dumper($cgi);
                close(TMP);
            }
        }
        exit;
    }

    my $html = [];

    my($pattern,$seq_pat,$tool,$ids,$subsearch);

    my $user = $cgi->param('user') || '';

    if ($cgi->param('Search for Genes Matching an Occurrence Profile or Common to a Set of Organisms'))
    {
        Trace("Gene search chosen.") if T(2);
        unshift @$html, "<TITLE>The SEED: Phylogenetic Signatures</TITLE>\n";
        $ENV{"REQUEST_METHOD"} = "GET";
        $ENV{"QUERY_STRING"} = "user=$user";
        my @out = `./sigs.cgi`;
        print @out;
        &done;
    }
    elsif ($cgi->param('Search for Genes in Cluster, but Not Subsystems'))
    {
        $ENV{"REQUEST_METHOD"} = "GET";
        $ENV{"QUERY_STRING"} = "user=$user";
        my @out = `./clust_ss.cgi`;
        print @out;
        &done;
    }

    #-----------------------------------------------------------------------
    #  Statistics for a single organism
    #-----------------------------------------------------------------------
    elsif ($cgi->param('statistics'))
    {
        Trace("Statistics chosen.") if T(2);
        @orgs = $cgi->param('korgs');
        @orgs = map { $_ =~ /(\d+\.\d+)/; $1 } @orgs;
        if (@orgs != 1)
        {
            unshift @$html, "<TITLE>The SEED Statistics Page</TITLE>\n";
            push(@$html,$cgi->h1('Please select a single organism to get statistcs'));
        }
        else
        {
            $ENV{"REQUEST_METHOD"} = "GET";
            $ENV{"QUERY_STRING"} = "user=$user&genome=$orgs[0]";
            my @out = `./genome_statistics.cgi`;
            print @out;
            &done;
        }
    }
    #-----------------------------------------------------------------------
    #  Locate PEGs in Subsystems
    #-----------------------------------------------------------------------
    elsif ($cgi->param('Find PEGs') && ($subsearch = $cgi->param('subsearch')))
    {
        Trace("PEG find chosen.") if T(2);
        my $genome = $cgi->param('genome');
        my (@pegs,$peg);

        my @poss = $fig->by_alias($subsearch);
        if (@poss > 0)    { $subsearch = $poss[0] }

        if ($subsearch =~ /(fig\|\d+\.\d+\.peg\.\d+)/)
        {
            #       handle searching for homologs that occur in subsystems
            $peg = $1;
            @pegs = ($peg);
            push(@pegs,map { $_->id2 } $fig->sims( $peg, 500, 1.0e-10, "fig"));
            if ($genome)
            {
                my $genomeQ = quotemeta $genome;
                @pegs = grep { $_ =~ /^fig\|$genomeQ/ } @pegs;
            }
        }
        else
        {
            #       handle searching for PEGs with functional role in subsystems
            @pegs = $fig->seqs_with_role($subsearch,"master",$genome);
        }

        print $cgi->header;
        if (@pegs == 0)
        {
            print $cgi->h1("Sorry, could not even find PEGs to check");
        }
        else
        {
            my(@pairs,$pair,@sub);
            @pairs = map { $peg = $_;
                           @sub = $fig->peg_to_subsystems($peg);
                           map { [$peg,$_] } @sub } @pegs;
            if (@pairs == 0)
            {
                print $cgi->h1("Sorry, could not map any PEGs to subsystems");
            }
            else
            {
                my($uni,$uni_func);
                my $col_hdrs = ["PEG","Genome","Function","UniProt","UniProt Function","Subsystem"];
                my $tab = [ map { $pair = $_; $uni = $fig->to_alias($pair->[0],"uni");
                                  ($uni,$uni_func) = $uni ? (&HTML::uni_link($cgi,$uni),scalar $fig->function_of($uni)) : ("","");
                                  [&HTML::fid_link($cgi,$pair->[0]),
                                   $fig->org_of($pair->[0]),
                                   scalar $fig->function_of($pair->[0]),
                                   $uni,$uni_func,
                                   &HTML::sub_link($cgi,$pair->[1])] } @pairs];
                print &HTML::make_table($col_hdrs,$tab,"PEGs that Occur in Subsystems");
            }
        }
        &done;
    }
    #-----------------------------------------------------------------------
    #  Align Sequences
    #-----------------------------------------------------------------------
    elsif ($cgi->param('Align Sequences'))
    {
        Trace("Sequence alignment chosen.");
        my $seqs = $cgi->param('seqids');
        $seqs =~ s/^\s+//;
        $seqs =~ s/\s+$//;
        my @seq_ids = split(/[ \t,;]+/,$seqs);
        if (@seq_ids < 2)
        {
            print $cgi->header;
            print $cgi->h1("Sorry, you need to specify at least two sequence IDs");
        }
        else
        {
            $ENV{"REQUEST_METHOD"} = "GET";
            $_ = join('&checked=',@seq_ids);
            $ENV{"QUERY_STRING"} = "user=$user&align=1&checked=" . $_;
            my @out = `./fid_checked.cgi`;
            print join("",@out);
        }
        &done;
    }
    #-----------------------------------------------------------------------
    #  Search (text) || Find Genes in Org that Might Play the Role
    #-----------------------------------------------------------------------
    elsif ( ( $pattern = $cgi->param('pattern') )
           && ( $cgi->param('Search')
               || $cgi->param('sphinx_search')
               || $cgi->param('Search genome selected below')
               || $cgi->param('Search Selected Organisms')
               || $cgi->param('Find Genes in Org that Might Play the Role')
              )
          )
    {
        Trace("Pattern search chosen.") if T(2);
        #  Remove leading and trailing spaces from pattern -- GJO:
        $pattern =~ s/^\s+//;
        $pattern =~ s/\s+$//;
        if ($cgi->param('Find Genes in Org that Might Play the Role') &&
            (@orgs = $cgi->param('korgs')) && (@orgs == 1))
        {
            unshift @$html, "<TITLE>The SEED: Genes in that Might Play Specific Role</TITLE>\n";
            @orgs = map { $_ =~ /(\d+\.\d+)/; $1 } @orgs;
            $ENV{"REQUEST_METHOD"} = "GET";
            $ENV{"QUERY_STRING"} = "user=$user&request=find_in_org&role=$pattern&org=$orgs[0]";
            my @out = `./pom.cgi`;
            print join("",@out);
            &done;
        }
        else
        {
            unshift @$html, "<TITLE>The SEED: Search Results</TITLE>\n";
            &show_indexed_objects($fig, $cgi, $html, $pattern, $user);
        }
    }
    #-----------------------------------------------------------------------
    #  Metabolic Overview
    #-----------------------------------------------------------------------
    elsif (($map = $cgi->param('kmap')) && $cgi->param('Metabolic Overview'))
    {
        Trace("Metabolic overview chosen.") if T(2);
        if ($map =~ /\(([^\)]*)\)$/)
        {
            $map = $1;
        }
        else
        {
            # ??? Gary ???
        }

        #$map =~ s/^.*\((MAP\d+)\).*$/$1/;
        @orgs = $cgi->param('korgs');
        @orgs = map { $_ =~ /(\d+\.\d+)/; $1 } @orgs;
        $ENV{"REQUEST_METHOD"} = "GET";
        if (@orgs > 0)
        {
            $ENV{"QUERY_STRING"} = "user=$user&map=$map&org=$orgs[0]";
        }
        else
        {
            $ENV{"QUERY_STRING"} = "user=$user&map=$map";
        }

        unshift @$html, "<TITLE>The SEED: Metabolic Overview</TITLE>\n";
        my @out = `./show_map.cgi`;
        &HTML::trim_output(\@out);
        push( @$html, "<br>\n", @out );
    }

    #-----------------------------------------------------------------------
    #  Search for Matches (sequence or pattern)
    #-----------------------------------------------------------------------
    elsif (($seq_pat = $cgi->param('seq_pat')) &&
           ($tool = $cgi->param('Tool')) &&
           $cgi->param('Search for Matches'))
    {
        Trace("Match search chosen.") if T(2);
        @orgs = $cgi->param('korgs');
        if (@orgs > 0)
        {
            @orgs = map { $_ =~ /(\d+\.\d+)/; $1 } @orgs;
        }
        else
        {
            @orgs = ("");
        }

        if ($tool =~ /blast/)
        {
            unshift @$html, "<TITLE>The SEED: BLAST Search Results</TITLE>\n";
            &run_blast($fig,$cgi,$html,$orgs[0],$tool,$seq_pat, $user);
        }
        elsif ($tool =~ /Identical SEED proteins/)
        {
            unshift @$html, "<TITLE>The SEED: Identical SEED Proteins</TITLE>\n";
            &identical_seed_proteins( $fig, $cgi, $html, $seq_pat, $user );
        }
        elsif ($tool =~ /Protein scan_for_matches/)
        {
            unshift @$html, "<TITLE>The SEED: Protein Pattern Match Results</TITLE>\n";
            &run_prot_scan_for_matches($fig,$cgi,$html,$orgs[0],$seq_pat);
        }
        elsif ($tool =~ /DNA scan_for_matches/)
        {
            unshift @$html, "<TITLE>The SEED: Nucleotide Pattern Match Results</TITLE>\n";
            &run_dna_scan_for_matches($fig,$cgi,$html,$orgs[0],$seq_pat);
        }
    }
    elsif (($made_by = $cgi->param('made_by')) && $cgi->param('Extract Assignments'))
    {
        Trace("Assignment export chosen.") if T(2);
        &export_assignments($fig,$cgi,$html,$made_by);
    }
    elsif ($cgi->param('Generate Assignments via Translation') &&
           ($from_func = $cgi->param('from_func')) &&
           ($to_func = $cgi->param('to_func')))
    {
        Trace("Assignment translate chosen.") if T(2);
        &translate_assignments($fig,$cgi,$html,$from_func,$to_func);
    }

    elsif ($cgi->param('Extract Matched Sequences') && ($ids = $cgi->param('ids')))
    {
        Trace("Matched sequence extract chosen.") if T(2);
        my @ids = split(/,/,$ids);

        #  Truncate the list if requested:

        my($list_to,$i);
        if ($list_to = $cgi->param('list_to'))
        {
            for ($i=0; ($i < @ids) && ($ids[$i] ne $list_to); $i++) {}
            if ($i < @ids)
            {
                $#ids = $i;
            }
        }

        #  Print the sequences:
        #     Add organisms -- GJO

        my( $id, $seq, $desc, $func, $org );
        push( @$html, $cgi->pre );
        foreach $id (@ids)
        {
            if ($seq = $fig->get_translation($id))
            {
                $desc  = $id;
                if ( $func = $fig->function_of( $id ) )
                {
                    $desc .= " $func";
                }
                if ( $org  = $fig->genus_species( $fig->genome_of( $id ) ) )
                {
                    $desc .= " [$org]" if $org;
                }
                push( @$html, ">$desc\n" );
                for ($i=0; ($i < length($seq)); $i += 60)
                {
                    #  substr does not mind a request for more than length
                    push( @$html, substr( $seq, $i, 60 ) . "\n" );
                }
            }
        }
        push(@$html,$cgi->end_pre);
    }

    #-----------------------------------------------------------------------
    #  Initial search page
    #-----------------------------------------------------------------------
    else
    {
        Trace("SEED Entry page chosen.") if T(2);
        unshift @$html, "<TITLE>The SEED: Entry Page</TITLE>\n";
        &show_initial($fig,$cgi,$html);
    }
    Trace("Showing page.") if T(3);
    &HTML::show_page($cgi,$html,1);
    Trace("Page shown.") if T(3);
}

#==============================================================================
#  Initial page (alias search)
#==============================================================================

sub show_initial {
    my($fig,$cgi,$html) = @_;
    my($map,$name,$olrg,$gs);


    #
    # Display the message of the day, if present.
    #

    show_motd($fig, $cgi, $html);

    #  The original $a and $b conflicted with explicit sort variables (ouch):
    #  "Can't use "my $a" in sort comparison" -- GJO

    my( $at, $bt, $et, $v, $envt ) = $fig->genome_counts;
    push(@$html,$cgi->h2("Contains $at archaeal, $bt bacterial, $et eukaryal, $v viral and $envt environmental genomes"));
    my( $ac, $bc, $ec ) = $fig->genome_counts("complete");
    push(@$html,$cgi->h2("Of these, $ac archaeal, $bc bacterial and $ec eukaryal genomes are more-or-less complete"),$cgi->hr);

    push(@$html,
         $cgi->h2('Work on Subsystems'),

#        $cgi->start_form(-action => "ssa2.cgi"),
#        "Enter user: ",
#        $cgi->textfield(-name => "user", -size => 20),
#        $cgi->submit('Work on Subsystems'),
#        $cgi->end_form,

#        $cgi->h2('Work on Subsystems Using New, Experimental Code'),
#         "This is the <i>new</i> subsystems code, and is now officially released.",
         $cgi->start_form(-action => "subsys.cgi", -target => '_blank'),
         "Enter user: ",
         $cgi->textfield(-name => "user", -size => 20),
         $cgi->submit('Work on Subsystems'),
         $cgi->end_form,
        );

    my $user = $cgi->param( 'user' ) || '';
    push(@$html,
         "Or, on this machine you can: <A HRef='SubsysEditor.cgi?user=$user'>Use the new Subsystem Editor</A>\n",
        );

    push(@$html,
         $cgi->hr,
         $cgi->h2('Work on FIGfams'),
         $cgi->start_form(-action => "ff.cgi", -target => '_blank'),
         "Enter user: ",
         $cgi->textfield(-name => "user", -size => 20),
         $cgi->submit('Work on FIGfams'),
         $cgi->end_form,
         $cgi->hr,
        );

    my $maxpeg  = defined( $cgi->param("maxpeg")  ) ? $cgi->param("maxpeg")  : 2500;
    my $maxrole = defined( $cgi->param("maxrole") ) ? $cgi->param("maxrole") :  100;
    push( @$html,
          $cgi->start_form(-action => $this_script, -target => '_blank', -name => 'main_form'),
          "<table>\n",
          "<tr>",
              "<td colspan=2>", $cgi->h2('Searching for Genes or Functional Roles Using Text'), "</td>",
              "<td align=right><a href='sdk_uniprot_search.cgi'>UniProt WebService Search</a></td>",
          "</tr>\n",
          "<tr>",
              "<td>Search Pattern: </td>",
              "<td>", $cgi->textfield(-name => "pattern", -size => 65), "</td>",
              "<td>", "Search <select name=search_kind>
                           <option value=DIRECT  >Directly</option>
                           <option value=GO  >Via Gene Ontology</option>
                           <option value=HUGO  >Via HUGO Gene Nomenclature Committee</option>
                       </select></td>",
          "</tr>\n",
          "<tr>",
              "<td>User ID:</td>",
              "<td>",
                  $cgi->textfield(-name => "user", -size => 20), " [optional] &nbsp; &nbsp; ",
                  "Max Genes: ", $cgi->textfield(-name => "maxpeg",  -size => 6, -value => $maxpeg,  -override => 1), "&nbsp; &nbsp; ",
                  "Max Roles: ", $cgi->textfield(-name => "maxrole", -size => 6, -value => $maxrole, -override => 1), "</td>",
              "<td>", $cgi->checkbox(-name => "substring_match",  -label => 'Allow substring match'), ' ',
                      $cgi->checkbox(-name => "suppress_aliases", -label => 'Suppress aliases'), "</td>",
          "</tr>\n",
          "</table>\n",
          ($FIG_Config::suppress_non_sphinx_search ? () : $cgi->submit('Search')),
          ($have_sphinx ? $cgi->submit(-name => "sphinx_search", -value => 'Search with Sphinx') : ()),
          $cgi->submit('Search genome selected below'),
          $cgi->reset('Clear'),
          $cgi->hr
        );

    #---------------------------------------------------------------------------
    #  Build the list of genomes from which the user can pick:
    #---------------------------------------------------------------------------

    my $link;
    $link = "$FIG_Config::cgi_url/show_log.cgi";

    push( @$html, $cgi->h2('If You Need to Pick a Genome for Options Below'),"&nbsp;[<a href=$link>Log</a>]");

my $hide = <<'Old_genome_selector';
    my @display = ( 'All', 'Archaea', 'Bacteria', 'Eucarya', 'Plasmids', 'Viruses', 'Environmental samples' );

    #  Canonical names must match the keywords used in the DBMS.  They are
    #  defined in compute_genome_counts.pl

    my %canonical = (
        'All'                   =>  undef,
        'Archaea'               => 'Archaea',
        'Bacteria'              => 'Bacteria',
        'Eucarya'               => 'Eukaryota',
        'Plasmids'              => 'Plasmid',
        'Viruses'               => 'Virus',
        'Environmental samples' => 'Environmental Sample'
        );

    my $req_dom = $cgi->param( 'domain' ) || 'All';
    my @domains = $cgi->radio_group( -name     => 'domain',
                                     -default  => $req_dom,
                                     -override => 1,
                                     -values   => [ @display ]
                                   );

    my $n_domain = 0;
    my %dom_num = map { ( $_ => $n_domain++ ) } @display;
    my $req_dom_num = $dom_num{ $req_dom } || 0;

    #  Plasmids, Viruses and Environmental samples must have completeness
    #  = All (that is how they are in the database).  Otherwise, default is
    #  Only "complete".

    my $req_comp = ( $req_dom_num > $dom_num{ 'Eucarya' } ) ? 'All'
                 : $cgi->param( 'complete' ) || 'Only "complete"';
    my @complete = $cgi->radio_group( -name     => 'complete',
                                      -default  => $req_comp,
                                      -override => 1,
                                      -values   => [ 'All', 'Only "complete"' ]
                        );

    #  Use $fig->genomes( complete, restricted, domain ) to get org list:

    my $complete = ( $req_comp =~ /^all$/i ) ? undef : "complete";

    my @orgs;
    my %org_labels;
    foreach my $org ($fig->genomes( $complete, undef, $canonical{ $req_dom } ))
    {
        my $label = compute_genome_label($fig, $org);
        $org_labels{$org} = $label;
        push(@orgs, $org);
    }

    #  Make the sort case independent -- GJO

    #  @orgs = sort { $a cmp $b } @orgs;
    @orgs = sort { lc( $org_labels{$a} ) cmp lc( $org_labels{$b} ) } @orgs;

    my $n_genomes = @orgs;

    #
    # Make a list of the org names for the code that doesn't use the
    # name/value separation in the scrolling list.
    #

    my @org_names = map { $org_labels{$_} } @orgs;

    push( @$html, "<TABLE>\n",
                  "  <TR VAlign=top>\n",
                  "    <TD>",
                  $cgi->scrolling_list( -name   => 'korgs',
                                        -values => [ @orgs ],
                                        -labels => \%org_labels,
                                        -size   => 10,
                                      ), $cgi->br,
                  "$n_genomes genomes shown ",
                  $cgi->submit( 'Update List' ), $cgi->reset, $cgi->br,
                  "Show some ", $cgi->submit('statistics')," of the selected genome",
                  "    </TD>",

                  "    <TD><b>Domain(s) to show:</b>\n",
                  "        <TABLE>\n",
                  "          <TR VAlign=bottom>\n",
                  "            <TD>", join( "<br>", @domains[0..3]), "</TD>\n",
                  "            <TD>&nbsp;&nbsp;&nbsp;</TD>\n",
                  "            <TD>", join( "<br>", @domains[4..$#domains]), "</TD>\n",
                  "          </TR>\n",
                  "        </TABLE>\n",
                  "        ", join( "<br>", "<b>Completeness?</b>", @complete), "\n",
                  "    </TD>",
                  "  </TR>\n",
                  "</TABLE>\n",
                  $cgi->hr
        );

Old_genome_selector

    #=============================#
    #  New genome selector begin  #
    #=============================#
    my $formname  = 'main_form';
    my $listname  = 'SEED_genomes';
    my $paramname = 'korgs';
    my $listopts  = { FilterTextSize => 72,
                      GenomeListSize => 10,
                    };

    #  Once per WWW page (this is specific to getting all SEED genomes)
    push @$html, GenomeSelector::genomeHTML( $fig, $listname );

    #  Once per WWW page
    push @$html, GenomeSelector::scriptHTML();

    #  Once per selection list
    push @$html, GenomeSelector::selectHTML( $formname, $listname, $paramname, $listopts );

    #===========================#
    #  New genome selector end  #
    #===========================#

    push( @$html, $cgi->h2('Finding Candidates for a Functional Role'),
                "Make sure that you type the functional role you want to search for in the Search Pattern above",
                $cgi->br,
                $cgi->submit('Find Genes in Org that Might Play the Role'),
                $cgi->hr);

    my @maps = sort map { $map = $_; $name = $fig->map_name($map); "$name ($map)" } $fig->all_maps;

    push( @$html, $cgi->h2('Metabolic Overviews and Subsystem Maps (via KEGG & SEED) - Choose Map'),
                  $cgi->submit('Metabolic Overview'),
                  $cgi->br,
                  $cgi->br,
                  $cgi->scrolling_list(-name => 'kmap',
                                       -values => [@maps],
                                       -size => 10
                                      ),
                  $cgi->hr);

    push( @$html, $cgi->h2('Searching DNA or Protein Sequences (in a selected organism)') );
    my $func_list = [ 'blastp',
                      'blastx',
                      'blastn',
                      'tblastn',
                      'blastp against complete genomes',
                      'Identical SEED proteins',
                      'Protein scan_for_matches',
                      'DNA scan_for_matches'
                    ];
    push( @$html, "<TABLE>\n",
                  "    <TR>\n",
                  "        <TD>Sequence/Pattern: </TD>",
                  "        <TD Colspan=3>", $cgi->textarea( -name => 'seq_pat',
                                                            -rows => 10,
                                                            -cols => 80
                                                          ), "</TD>\n",
                  "    </TR>\n",
                  "    <TR>\n",
                  "        <TD>Search Program: </TD>",
                  "        <TD>", $cgi->popup_menu( -name    => 'Tool',
                                                    -values  => $func_list,
                                                    -default => 'blastp'
                                                  ), " </TD>",
                  "        <TD> Program Options:</TD>",
                  "        <TD>", $cgi->textfield( -name => "blast_options", -size => 27 ), "</TD>",
                  "    </TR>\n",
                  "</TABLE>\n",
                  $cgi->submit('Search for Matches'),
                  $cgi->hr);

    #
    # Make assignment export tbl.
    #

    my @atbl;
    push(@atbl, [ "Extract assignments made by ",
                  $cgi->textfield(-name => "made_by", -size => 25) . " (do not prefix with <b>master:</b>)" ]);
    push(@atbl, [ "Save as user: ",
                  $cgi->textfield(-name => "save_user", -size => 25) . " (do not prefix with <b>master:</b>)" ] );
    push(@atbl, [ "After date (MM/DD/YYYY) ",
                  $cgi->textfield(-name => "after_date", -size => 15)]);

    push(@$html,
         $cgi->h2($cgi->a({name => "exporting_assignments"}, 'Exporting Assignments')),
         &HTML::make_table(undef, \@atbl, '', border => 0),
                $cgi->checkbox(-label => 'Tab-delimited Spreadsheet', -name => 'tabs', -value => 1),
                $cgi->br,
                $cgi->checkbox(-label => 'Save Assignments', -name => 'save_assignments', -value => 1),
                $cgi->br,
                $cgi->submit('Extract Assignments'),
                $cgi->br, $cgi->br, $cgi->br,
                "Alternatively, you can generate a set of assignments as translations of existing assignments.  ",
                "To do so, you need to make sure that you fill in the <b>Save as user</b> field just above.  You ",
                "should use something like <b>RossO</b> (leave out the <b>master:</b>).  When you look at the assignments (and decide which ",
                "to actually install), they will be made available under that name (but, when you access them, ",
                "you will normally be using something like <b>master:RossO</b>)",
                $cgi->br,$cgi->br,
                "From: ",
                $cgi->textarea(-name => 'from_func', -rows => 4, -cols => 100),
                $cgi->br,$cgi->br,
                "To:&nbsp;&nbsp;&nbsp;&nbsp; ",$cgi->textfield(-name => "to_func", -size => 100),
                $cgi->br,
                "<TABLE Width=100%><TR><TD>",
                $cgi->submit('Generate Assignments via Translation'),
                "</TD><TD NoWrap Width=1%>",
                $cgi->a({class=>"help", target=>"help", href=>"Html/seedtips.html#replace_names"}, "Help with generate assignments via translation"),
                "</TD></TR></TABLE>\n"
         );

    push(@$html,
                $cgi->hr,
                $cgi->h2('Searching for Interesting Genes'),
                $cgi->submit('Search for Genes Matching an Occurrence Profile or Common to a Set of Organisms'),
                $cgi->submit('Search for Genes in Cluster, but Not Subsystems'),
                $cgi->end_form
         );

    push(@$html,
                $cgi->hr,
                $cgi->h2('Process Saved Assignments Sets'),
                $cgi->start_form(-action => "assignments.cgi", -target => '_blank'),
                "Here you should include the <b>master:</b>.  Thus use something like <b>master:RossO</b>",$cgi->br,
                $cgi->br,
                "Enter user: ",
                $cgi->textfield(-name => "user", -size => 20),
                $cgi->submit('Process Assignment Sets'),
                $cgi->end_form
         );

    push(@$html,
                $cgi->hr,
                $cgi->h2('Locate clustered genes not in subsystems'),
                $cgi->start_form(-action => "find_ss_genes.cgi", -target => '_blank'),
                $cgi->br,
                "Enter user: ",
                $cgi->textfield(-name => "user", -size => 20),
                $cgi->submit('Find Clustered Genes'),
                $cgi->end_form
         );

    push(@$html,
                $cgi->hr,
                $cgi->h2('Align Sequences'),
                $cgi->start_form(-action => $this_script, -target => '_blank'),
                "Enter user: ",
                $cgi->textfield(-name => "user", -size => 20), $cgi->br,
                $cgi->submit('Align Sequences'),": ",
                $cgi->textfield(-name => "seqids", -size => 100),
                $cgi->end_form
         );

    push(@$html,
                $cgi->hr,
                $cgi->h2('Locate PEGs in Subsystems'),
                "If you wish to locate PEGs in subsystems, you have two approaches supported.  You can
give a FIG id, and you will get a list of all homologs in the designated genome that occur in subsystems.
Alternatively, you can specify a functional role, and all PEGs in the genome that match that role will be shown.",
                $cgi->start_form(-action => $this_script, -target => '_blank'),
                "Enter user: ",
                $cgi->textfield(-name => "user", -size => 20), $cgi->br,
                $cgi->br,"Genome: ",$cgi->textfield(-name => "genome", -size => 15),$cgi->br,
                "Search: ",$cgi->textfield(-name => "subsearch", -size => 100),$cgi->br,
                $cgi->submit('Find PEGs'),": ",
                $cgi->end_form
         );
    push(@$html,
                $cgi->hr,
                $cgi->h2('Compare Metabolic Reconstructions'),
                "If you wish to compare the reconstructions for two distinct genomes, use this tool.
You should specify two genomes, or a P1K server output directory (as genome1) and a second genome (which
must be a valid genome ID that exists in this SEED).  You can ask for functional roles/subsystems that the
genomes have in common, those that exist in genome1 only, or those that exist in only genome2.",
                $cgi->start_form(-action => 'comp_MR.cgi', -target => '_blank'),
                "Enter user: ",
                $cgi->textfield(-name => "user", -size => 20), $cgi->br,
                $cgi->br,"Genome1: ",$cgi->textfield(-name => "genome1", -size => 40),$cgi->br,
                $cgi->br,"Genome2: ",$cgi->textfield(-name => "genome2", -size => 15),
                $cgi->scrolling_list( -name   => 'request',
                                      -values => [ 'common', 'in1_not2','in2_not1' ],
                                        -size   => 3,
                                      ), $cgi->br,
                $cgi->submit('Compare Reconstructions'),": ",
                $cgi->end_form
        );

    push(@$html,
                $cgi->hr,
                $cgi->h2('Compare Genomes'),
                "If you wish to compare the contents of several genomes, you can use this tool.
Choose a set of genomes (at least two).<br><br> ",
                $cgi->start_form(-action => 'comp_genomes.cgi', -target => '_blank', -name => 'comp_genomes' ),
                "Enter user: ",
                $cgi->textfield(-name => "user", -size => 20), $cgi->br);

    #=============================#
    #  New genome selector begin  #
    #=============================#
    my $formname2  = 'comp_genomes';
    my $listname2  = 'SEED_genomes';
    my $paramname2 = 'comp_orgs';
    my $listopts2  = { FilterTextSize => 72,
                       GenomeListSize => 10,
                       Multiple       =>  1
                     };

    #  Once per WWW page (this is specific to getting all SEED genomes)
    # push @$html, GenomeSelector::genomeHTML( $fig, $listname2 );

    #  Once per WWW page
    # push @$html, GenomeSelector::scriptHTML();

    #  Once per selection list
    push @$html, GenomeSelector::selectHTML( $formname2, $listname2, $paramname2, $listopts2 );

    #===========================#
    #  New genome selector end  #
    #===========================#

    push(@$html,
                 "Optionally, you can select a PEG and window size to limit the comparison:<br>",
                "PEG: ", $cgi->textfield(-name => "peg", -size => 20), $cgi->br,
                "Window Size: ", $cgi->textfield(-name => "sz", -size => 8, -value => 20000), $cgi->br,

                $cgi->submit('Compare Genomes'),
                $cgi->submit('Update Functions in MouseOvers'),"<br>",
                $cgi->end_form
        );

    push(@$html,
                $cgi->hr,
                $cgi->h2('New Pattern Matching'),
                "The new pattern location tool.<br><br> ",
                $cgi->start_form(-action => 'locate_patterns.cgi', -target => '_blank', -name => 'pat_scan' ),
                "Enter user (optional): ",
                $cgi->textfield(-name => "user", -size => 20), $cgi->br);

    #=============================#
    #  New genome selector begin  #
    #=============================#
    my $formname3  = 'pat_scan';
    my $listname3  = 'SEED_genomes';
    my $paramname3 = 'comp_orgs';
    my $listopts3  = { FilterTextSize => 72,
                       GenomeListSize => 10,
                       Multiple       =>  1
                     };

    #  Once per WWW page (this is specific to getting all SEED genomes)
    # push @$html, GenomeSelector::genomeHTML( $fig, $listname3 );

    #  Once per WWW page
    # push @$html, GenomeSelector::scriptHTML();

    #  Once per selection list
    push @$html, GenomeSelector::selectHTML( $formname3, $listname3, $paramname3, $listopts3 );

    #===========================#
    #  New genome selector end  #
    #===========================#

    push @$html, "Pattern: ", $cgi->textfield(-name => "pattern", -size => 60), $cgi->br,
                $cgi->popup_menu(-name => 'Tool',
                                 -values => ['Protein scan_for_matches', 'DNA scan_for_matches'],
                                 -default => 'Protein scan_for_matches'),
                $cgi->submit('Scan For Matches'),
                $cgi->end_form;
}

sub compute_genome_label
{
    my($fig, $org) = @_;

    my $label;
    my $gs = $fig->genus_species($org);
    if ($fig->genome_domain($org) ne "Environmental Sample")
    {
        my $gc=$fig->number_of_contigs($org);
        $label = "$gs ($org) [$gc contigs]";
    }
    else
    {
        $label = "$gs ($org)";
    }
    return $label;
}

#
# Show a message of the day if it's present.
#
sub show_motd
{
    my($fig, $cgi, $html) = @_;

    my $motd_file = "$FIG_Config::fig_disk/config/motd";

    if (open(F, "<$motd_file"))
    {
        push(@$html, "<p>\n");
        while (<F>)
        {
            push(@$html, $_);
        }
        close(F);
        push(@$html, "<hr>\n");
    }
}

#==============================================================================
#  Indexed objects (text search)
#==============================================================================

sub show_indexed_objects {
    my($fig, $cgi, $html, $pattern, $user) = @_;
    my($msg, $i);

    #  Does it look like a SEED identifer?
    if ($pattern =~ /^\s*(fig\|\d+\.\d+\.peg\.\d+)\s*$/)
    {
        my $peg = $1;
        my $user = $cgi->param('user');
        $user = $user ? $user : "";
#         my @prot_out;
#         if (defined($cgi->param('fromframe'))) {
#           $ENV{'REQUEST_METHOD'} = "GET";
#           $ENV{"QUERY_STRING"} = "prot=$peg\&user=$user\&action=proteinpage";
#           $ENV{"REQUEST_URI"} =~ s/$this_script/frame.cgi/;
#           $ENV{"SCRIPT_NAME"} =~ s/$this_script/frame.cgi/;
#           @prot_out = TICK("./frame.cgi");
#         } else {
#           $ENV{'REQUEST_METHOD'} = "GET";
#           $ENV{"QUERY_STRING"} = "prot=$peg\&user=$user";
#           $ENV{"REQUEST_URI"} =~ s/$this_script/protein.cgi/;
#           $ENV{"SCRIPT_NAME"} =~ s/$this_script/protein.cgi/;
#           @prot_out = TICK("./protein.cgi");
#         }
#         print @prot_out;
        if ($FIG_Config::anno3_mode) {
            print $cgi->redirect("seedviewer.cgi?page=Annotation&feature=$peg&user=$user");
        } else {
            print $cgi->redirect("protein.cgi?prot=$peg&user=$user");
        }
        &done;
    }

    #  Does it look like an MD5?
    elsif ( $pattern =~ /^\s*([0-9A-Za-z]{32})\s*$/ )
    {
        my $md5 = $1;
        md5_prot_table( $fig, $cgi, $html, $md5, 'user-supplied MD5' );
        return;
    }

    $pattern =~ s/([a-zA-Z0-9])\|([a-zA-Z0-9])/$1\\\|$2/ig;

    my $search_kind = $cgi->param("search_kind");
    if ( $search_kind && ! ($search_kind eq "DIRECT") ) {
        #otherwise $search_kind is name of controlled vocab
        find_pegs_by_cv($fig, $cgi, $html, $user, $pattern, $search_kind);
        return;
    }

    push( @$html, $cgi->br );

    my $maxpeg  = defined( $cgi->param("maxpeg")  ) ? $cgi->param("maxpeg")  : 2500;
    my $maxrole = defined( $cgi->param("maxrole") ) ? $cgi->param("maxrole") :  100;
    my( $peg_index_data, $role_index_data );

    if ($cgi->param('sphinx_search') && @FIG_Config::sphinx_params)
    {
        my $sphinx = Sphinx::Search->new();
        $sphinx->SetServer(@FIG_Config::sphinx_params);

        my $offset = ($cgi->param('sphinx_offset') || '') =~ /(\d+)/ ? $1 : 0;
        $sphinx->SetLimits($offset, $maxpeg);
        $sphinx->SetMatchMode($sphinx_search_mode);
        # print STDERR "pattern=$pattern\n";
        my $res = $sphinx->Query($pattern, 'feature_all_index');

        $offset += $maxpeg;
        $cgi->param(sphinx_offset => $offset);
        push(@$html,
             $cgi->start_form(-method => 'post',
                              -action => 'index.cgi',
                              -target => '_blank'
                             ),
             $cgi->hidden(-name => 'sphinx_offset',    -value => $offset),
             $cgi->hidden(-name => 'suppress_aliases', -value => $cgi->param('suppress_aliases')),
             $cgi->hidden(-name => 'maxpeg',           -value => $maxpeg),
             $cgi->hidden(-name => 'pattern',          -value => $cgi->param('pattern')),
             $cgi->submit(-name => 'sphinx_search',    -value => "More hits"),
             $cgi->end_form());


        $peg_index_data = [];
        $role_index_data = [];

        my @fids;

        for my $row (@{$res->{matches}})
        {
            my $doc = $row->{doc};
            my $fid = SeedSearch::docid_to_fid($doc);
            print STDERR Dumper($doc, $fid);
            next unless $fig->is_real_feature($fid);
            push(@fids, $fid);
        }

        my $fns = $fig->function_of_bulk(\@fids);
        my $aliases = {};
        if (!$cgi->param('suppress_aliases'))
        {
            $aliases = $fig->feature_aliases_bulk(\@fids);
        }

        for my $fid (@fids)
        {
            my $fn = $fns->{$fid};
            my $aliases = $aliases->{$fid} ? join(" ", @{$aliases->{$fid}}) : "";
            my $gs = $fig->genus_species(&FIG::genome_of($fid));

            push(@$peg_index_data, [$fid, $gs, $aliases, $fn]);
        }
    }
    else
    {
        ( $peg_index_data, $role_index_data ) = $fig->search_index($pattern, $cgi->param("substring_match") eq "on");
    }

    my $output_file = "$FIG_Config::temp/search_results.txt";
    Trace("Producing search output file $output_file") if T(3);
    open(OUT,">$output_file");

    # RAE added lines to allow searching within a single organism
    # if ($cgi->param('korgs'))
    # {
    #  $cgi->param('korgs') =~ /\((\d+\.*\d*)\)/;
    #  $org=$1; # this should be undef if korgs is not defined

    #  push (@$html, $cgi->br, "Matches found in ",$cgi->param('korgs'), $cgi->p);
    #  my @clean_data; my @clean_index;
    #  while (@$peg_index_data)
    #  {
    #   my ($data, $index)=(shift @$peg_index_data, shift @$role_index_data);
    #   next unless (${$data}[0] =~ /^fig\|$org\.peg/);
    #   push @clean_data, $data;
    #   push @clean_index, $index;
    #  }

    #  @$peg_index_data=@clean_data;
    #  @$role_index_data=@clean_index;
    # }
    ## End of added lines

    # RAE version with separate submit buttoxns and more than one org in korg
    # this is used by organisms.cgi for group specific searches
    if ( $cgi->param('korgs') && $cgi->param('Search Selected Organisms')
       )
    {
      my %orgs = map { $_ => 1 } $cgi->param('korgs');
      @$peg_index_data = grep { $orgs{ FIG::genome_of( $_->[0] ) } } @$peg_index_data;
    }

    # GJO version with separate submit buttons

    if ( $cgi->param('korgs') && $cgi->param('korgs') =~ /(\d+\.\d+)/
                              && $cgi->param('Search genome selected below')
       )
    {
        my $org = $1;
        my $label = compute_genome_label($fig, $org);
        push @$html, $cgi->br, "Matches found in $label", $cgi->br;
        @$peg_index_data = grep { FIG::genome_of( $_->[0] ) eq $org } @$peg_index_data;
    }

    Trace("Initial push.") if T(3);
    if ( ( $maxpeg > 0 ) && @$peg_index_data )
    {
        # RAE: Added javascript buttons see below. Only two things are needed.
        # The form must have a name parameter, and the one line of code for the
        # buttons. Everything else is automatic

        push( @$html, $cgi->start_form( -method => 'post',
                                        -target => '_blank',
                                        -action => 'fid_checked.cgi',
                                        -name   => 'found_pegs'
                                      ),
                      $cgi->hidden(-name => 'user', -value => $user),
                      "For Selected (checked) sequences: ",
                      $cgi->submit('get sequences'),
                      $cgi->submit('view annotations'),
                      $cgi->submit('assign/annotate'),
                      $cgi->param('SPROUT') ? () : $cgi->submit('view similarities'),
                      $cgi->br, $cgi->br
            );

        # RAE Add the check all/uncheck all boxes.
        push (@$html, $cgi->br, &HTML::java_buttons("found_pegs", "checked"), $cgi->br);

        my $n = @$peg_index_data;
        if ($n > $maxpeg)
        {
            $msg = "Showing first $maxpeg out of $n protein genes";
            $#{$peg_index_data} = $maxpeg-1;
        }
        else
        {
            $msg = "Showing $n FEATURES";
        }

        my $col_hdrs = ["Sel","FEATURE","Organism","Aliases","Functions","Who","Attributes"];
        my $tab = [ map { format_peg_entry( $fig, $cgi, $_ ) } sort {$a->[1] cmp $b->[1]} @$peg_index_data ];

        my $tab2 = [ sort {$a->[1] cmp $b->[1]} @$peg_index_data ];
        Trace("Final html push.") if T(3);
        push( @$html,$cgi->br,
                      "<a href=$FIG_Config::temp_url/search_results.txt>Download_Search_Results</a>",
                      &HTML::make_table($col_hdrs,$tab,$msg),
                      $cgi->br,
                      "For SELECTed (checked) sequences: ",
                      $cgi->submit('get sequences'),
                      $cgi->submit('view annotations'),
                      $cgi->submit('assign/annotate'),
                      $cgi->param('SPROUT') ? () : $cgi->submit('view similarities'),
                      $cgi->br,
                      $cgi->end_form
         );

        foreach my $t (@$tab2){
                my $string = join("\t",@$t);
                print OUT "$string\n";
        }

    }
    elsif ( $maxpeg > 0 )
    {
        push @$html, $cgi->h3('No matching protein genes');
    }

    if ( ( $maxrole > 0 ) && @$role_index_data )
    {
        my $n = @$role_index_data;
        if ($n > $maxrole)
        {
            $msg = "Showing first $maxrole out of $n Roles";
            $#{$role_index_data} = $maxrole - 1;
        }
        else
        {
            $msg = "Showing $n Roles";
        }

        if ( $maxpeg > 0 ) { push( @$html, $cgi->hr ) }
        my $col_hdrs = ["Role"];
        my $tab = [ map { &format_role_entry($fig,$cgi,$_) } @$role_index_data ];
        push( @$html, &HTML::make_table($col_hdrs,$tab,$msg) );
    }
    elsif ( $maxrole > 0 )
    {
        push @$html, $cgi->h3('No matching roles');
    }
    Trace("Show-indexed-objects method complete.") if T(3);
}

sub format_peg_entry {
    my( $fig, $cgi, $entry ) = @_;

    my($peg,$gs,$aliases,$function,$who,$attribute) = @$entry;

    $gs =~ s/\s+\d+$//;   # Org name comes with taxon_id appended (why?) -- GJO

    my $box = "<input type=checkbox name=checked value=\"$peg\">";
    my $peg_link;
    if ($FIG_Config::anno3_mode) {
        my $user = $cgi->param('user');
        $peg_link = "<a href=seedviewer.cgi?page=Annotation&feature=$peg&user=$user>$peg</a>";
    } else {
        $peg_link = &HTML::fid_link($cgi,$peg);
    }
    return [ $box, $peg_link, $gs, $aliases, $function, $who ];
}

sub format_role_entry {
    my($fig,$cgi,$entry) = @_;

    return [&HTML::role_link($cgi,$entry)];
}

sub run_prot_scan_for_matches {
    my($fig,$cgi,$html,$org,$pat) = @_;
    my($string,$peg,$beg,$end,$user,$col_hdrs,$tab,$i);

    my $tmp_pat = "$FIG_Config::temp/tmp$$.pat";
    open(PAT,">$tmp_pat")
        || die "could not open $tmp_pat";
    $pat =~ s/[\s\012\015]+/ /g;
    print PAT "$pat\n";
    close(PAT);
    my @out = `$FIG_Config::ext_bin/scan_for_matches -p $tmp_pat < $FIG_Config::organisms/$org/Features/peg/fasta`;
    if (@out < 1)
    {
        push(@$html,$cgi->h1("Sorry, no hits"));
    }
    else
    {
        if (@out > 2000)
        {
            push(@$html,$cgi->h1("truncating to the first 1000 hits"));
            $#out = 1999;
        }

        push(@$html,$cgi->pre);
        $user = $cgi->param('user');
        $col_hdrs = ["peg","begin","end","string","function of peg"];
        for ($i=0; ($i < @out); $i += 2)
        {
            if ($out[$i] =~ /^>([^:]+):\[(\d+),(\d+)\]/)
            {
                $peg = $1;
                $beg = $2;
                $end = $3;
                $string = $out[$i+1];
                chomp $string;
                push( @$tab, [ &HTML::fid_link($cgi,$peg,1),
                               $beg,
                               $end,
                               $string,
                               scalar $fig->function_of( $peg, $user )
                             ]
                    );
            }
        }
        push(@$html,&HTML::make_table($col_hdrs,$tab,"Matches"));
        push(@$html,$cgi->end_pre);
    }
    unlink($tmp_pat);
}

#==============================================================================
#  Scan for matches
#==============================================================================

sub run_dna_scan_for_matches {
    my($fig,$cgi,$html,$org,$pat) = @_;
    my($string,$contig,$beg,$end,$col_hdrs,$tab,$i);

    my $tmp_pat = "$FIG_Config::temp/tmp$$.pat";
    open(PAT,">$tmp_pat")
        || die "could not open $tmp_pat";
    $pat =~ s/[\s\012\015]+/ /g;
    print PAT "$pat\n";
    close(PAT);
    my @out = `cat $FIG_Config::organisms/$org/contigs | $FIG_Config::ext_bin/scan_for_matches -c $tmp_pat`;
    if (@out < 1)
    {
        push(@$html,$cgi->h1("Sorry, no hits"));
    }
    else
    {
        if (@out > 2000)
        {
            push(@$html,$cgi->h1("truncating to the first 1000 hits"));
            $#out = 1999;
        }

        push(@$html,$cgi->pre);
        $col_hdrs = ["contig","begin","end","string"];
        for ($i=0; ($i < @out); $i += 2)
        {
            if ($out[$i] =~ /^>([^:]+):\[(\d+),(\d+)\]/)
            {
                $contig = $1;
                $beg = $2;
                $end = $3;
                $string = $out[$i+1];
                chomp $string;
                push(@$tab,[$contig,$beg,$end,$string]);
            }
        }
        push(@$html,&HTML::make_table($col_hdrs,$tab,"Matches"));
        push(@$html,$cgi->end_pre);
    }
    unlink($tmp_pat);
}

#==============================================================================
#  BLAST search
#==============================================================================

sub run_blast {
    my( $fig, $cgi, $html, $org, $tool, $seq, $user ) = @_;
    my( $query, @out );

    my $tmp_seq = "$FIG_Config::temp/run_blast_tmp$$.seq";

    #--------------------------------------------------------------------------
    #  Does the request require a defined genome?  We never check that the
    #  database build works, so the least we can do is some up-front tests.
    #  -- GJO
    #--------------------------------------------------------------------------

    if ( $tool !~ /complete genomes/ )
    {
        if ( ! $org || ! -d "$FIG_Config::organisms/$org" )
        {
            push @$html, $cgi->h2("Sorry, $tool requires selecting a genome." );
            return;
        }

        if ( ( $tool =~ /blastn/ ) || ( $tool =~ /tblastx/ ) )
        {
            if ( ! -f "$FIG_Config::organisms/$org/contigs" )
            {
                push @$html, $cgi->h2("Sorry, cannot find DNA data for genome $org." );
                return;
            }
        }
        else
        {
            if ( ! -f "$FIG_Config::organisms/$org/Features/peg/fasta" )
            {
                push @$html, $cgi->h2("Sorry, cannot find protein data for genome $org." );
                return;
            }
        }
    }

    #--------------------------------------------------------------------------
    #  Is the request for an id?  Get the sequence
    #--------------------------------------------------------------------------

    if ( ( $query ) = $seq =~ /^\s*([a-zA-Z]{2,4}\|\S+)/ )
    {
        # Replaced $id with $query so that output inherits label -- GJO
        # Found ugly fairure to build correct query sequence for
        #     'blastp against complete genomes'.  Can't figure out
        #     why it ever worked with an id -- GJO

        $seq = "";
        if ( ($tool eq "blastp") || ($tool eq "tblastn")
                                 || ($tool eq 'blastp against complete genomes')
           )
        {
            $seq = $fig->get_translation($query);
            my $func = $fig->function_of( $query, $user );
            $query .= " $func"  if $func;
        }
        elsif ($query =~ /^fig/)
        {
            my @locs;
            if ((@locs = $fig->feature_location($query)) && (@locs > 0))
            {
                $seq = $fig->dna_seq($fig->genome_of($query),@locs);
            }
        }
        if (! $seq)
        {
            push(@$html,$cgi->h1("Sorry, could not get sequence for $query"));
            return;
        }
    }

    #--------------------------------------------------------------------------
    #  Is it a fasta format?  Get the query name
    #--------------------------------------------------------------------------

    elsif ( $seq =~ s/^\s*>\s*(\S+[^\n\012\015]*)// )  #  more flexible match -- GJO
    {
        $query = $1;
    }

    #--------------------------------------------------------------------------
    #  Take it as plain text
    #--------------------------------------------------------------------------

    else
    {
        $query = "query";
    }

    #
    #  Everything remaining is taken as the sequence
    #

    $seq =~ s/\s+//g;

    my $orgdir = "$FIG_Config::organisms/$org";
    if ( ! -d $orgdir )
    {
        push @$html, "\n<H2>Genome directory not available for genome '$org'</H2>\n";
        return;
    }

    if (! $ENV{"BLASTMAT"}) { $ENV{"BLASTMAT"} = "$FIG_Config::blastmat" }

    my $qseq = [ $query =~ /^(\S+)\s+(\S.*)$/ ? ( $1, $2 ) : ( $query, '' ), $seq ];

    my $blopt  = $cgi->param( 'blast_options' ) || '';
    my @blast_opt = $blopt =~ /\S/ ? split ' ', $blopt : ();

    if ( $tool eq 'blastp against complete genomes' )     ### this tool gets nonstandard treatment: RAO
    {
        gjoseqlib::write_fasta( $tmp_seq, [ $qseq ] );
        &blast_complete( $fig, $cgi, $html, $tmp_seq, $query, $seq );
        unlink( $tmp_seq );
        return;
    }

    my $dbfile = $tool =~ /^blast[px]$/ ? "$orgdir/Features/peg/fasta"
                                        : "$orgdir/contigs";
    if ( ! -s $dbfile )
    {
        push @$html, "\n<H2>Sequence data not available for genome '$org'</H2>\n";
        return;
    }

    my $genome = $fig->genus_species( $org );
    push @$html, "<H2>Searching for $tool matches in $genome [$org]</H2>\n";

    my @hsps;
    if ( $tool eq "blastp" )
    {
        @hsps = grep { $fig->is_real_feature( $_->[3] ) }
                execute_blast( $tool, $qseq, $dbfile, @blast_opt );

        my %fids = map { $_->[3] => 1 } @hsps;
        my $func = $fig->function_of_bulk( [keys %fids], 'no_del_check' );

        foreach ( @hsps )
        {
            $_->[4] = $func->{ $_->[3] } || '';
            $_->[3] = set_fid_link( $cgi, $_->[3] );
        }

        @out  = BlastInterface::hsps_to_text( \@hsps, $tool, {} );
    }

    elsif ( $tool eq "blastx" )
    {
        @hsps = grep { $fig->is_real_feature( $_->[3] ) }
                execute_blast( $tool, $qseq, $dbfile, @blast_opt );

        my %fids = map { $_->[3] => 1 } @hsps;
        my $func = $fig->function_of_bulk( [keys %fids], 'no_del_check' );

        foreach ( @hsps )
        {
            $_->[4] = $func->{ $_->[3] } || '';
            $_->[3] = set_fid_link( $cgi, $_->[3] );
        }

        @out  = BlastInterface::hsps_to_text( \@hsps, $tool, {} );
    }

    elsif ( $tool eq "blastn" )
    {
        @hsps = execute_blast( $tool, $qseq, $dbfile, @blast_opt );
        push @$html, blast_graphics( $fig, $cgi, $org, \@hsps, $tool );
        @out  = BlastInterface::hsps_to_text( \@hsps, $tool, {} );
    }

    elsif ( $tool eq "tblastn" )
    {
        @hsps = execute_blast( $tool, $qseq, $dbfile, @blast_opt );
        push @$html, blast_graphics( $fig, $cgi, $org, \@hsps, $tool );
        @out  = BlastInterface::hsps_to_text( \@hsps, $tool, {} );
    }

    push @$html, @out ? ( $cgi->pre, @out, $cgi->end_pre )
                      : $cgi->h2( "Sorry, no blast matches" );
}


sub set_fid_link
{
    my ( $cgi, $fid, $opts, $seed ) = @_;
    $fid =~ /^fig\|\d+\.\d+\.([^.]+)\.\d+$/
        or return $fid;

    my $prot   = $1 eq 'peg';
    my $opts ||= {};
    $seed ||= $opts->{seed};

    my @params = ( '' );

    my $user   = $cgi->param('user') || '';
    push @params, "user=$user" if $user;

    my $params = join( '&', @params );
    my $url = ! $seed ? "seedviewer.cgi?page=Annotation&feature=$fid" . $params
            :   $prot ? "protein.cgi?prot=$fid"                       . $params
            :           "feature.cgi?feature=$fid"                    . $params;

    my $tag = qq(A HRef="$url");
    $tag   .= qq( Class="$opts->{class}")     if $opts->{class};
    $tag   .= qq( Style="$opts->{style}")     if $opts->{style};
    $tag   .= qq( OnClick="$opts->{onclick}") if $opts->{onclick};

    "<$tag>$fid</A>";
}


#==============================================================================
#  Identical SEED proteins
#==============================================================================

sub identical_seed_proteins
{
    my( $fig, $cgi, $html, $seq, $user ) = @_;

    #--------------------------------------------------------------------------
    #  Is the request for an id?  Get the MD5
    #--------------------------------------------------------------------------

    my( $query, $md5, @out );
    if ( ( $query ) = $seq =~ /^\s*([a-zA-Z]{2,4}\|\S+)/ )
    {
        # Replaced $id with $query so that output inherits label -- GJO
        # Found ugly failure to build correct query sequence for
        #     'blastp against complete genomes'.  Can't figure out
        #     why it ever worked with an id -- GJO

        $md5 = $fig->md5_of_peg( $query );
    }

    #--------------------------------------------------------------------------
    #  It is an MD5 (exactly 32 hex characters)?
    #--------------------------------------------------------------------------

    elsif ( ( $md5 ) = $seq =~ /^\s*([0-9A-Fa-f]{32})\s*$/ )
    {
        $query = 'md5';
    }

    #--------------------------------------------------------------------------
    #  It is a sequence.  Compute the MD5.
    #--------------------------------------------------------------------------

    else
    {
        $query = ( $seq =~ s/^\s*>([^\n\012\015]*)// ) ? $1 : 'query';
        $seq   =~ s/[^A-Za-z]+//g;
        $md5   = $seq ? Digest::MD5::md5_hex( uc $seq ) : '';
    }

    md5_prot_table( $fig, $cgi, $html, $md5, $query );
    return;
}


sub md5_prot_table
{
    my ( $fig, $cgi, $html, $md5, $query ) = @_;
    $query = 'query' unless defined $query && length( $query );

    if ( ! $md5 )
    {
        push @$html, $cgi->h2( "Sorry, could not get sequence for $query" );
        return;
    }

    my $col_hdrs = [ 'ID', 'Genome', 'Function' ];

    my @rows = map  { [ $_->[1], [ $_->[2], "TD BgColor=$_->[3]" ], $_->[4] ] }
               sort { lc $a->[2] cmp lc $b->[2]
                   ||    $a->[5] <=>    $b->[5]
                   ||    $a->[6] <=>    $b->[6]
                   ||    $a->[7] <=>    $b->[7]
                    }
               map  { [ $_,                              # fid
                        HTML::fid_link( $cgi, $_ ),      # fid_link
                        $fig->org_and_color_of( $_ ),    # genus_species, html_color
                        scalar $fig->function_of( $_ ),  # func
                        /\|(\d+)\.(\d+)\.[^.]+\.(\d+)/   # taxid, genver, pegnum
                      ]
                    }
               $fig->is_real_feature_bulk( [ $fig->pegs_with_md5( $md5 ) ] );

    if ( @rows )
    {
        push( @$html, $cgi->br, $cgi->br, "\n",
                      &HTML::make_table($col_hdrs, \@rows, "SEED proteins identical to $query" )
            );
    }
    else
    {
        push( @$html, $cgi->h2( "No SEED proteins identical to $query" ) );
    }

    return;
}


#
#   @blast_text = remove_deleted_fids( $fig, @blast_text )
#
#  The blast datebases include all the proteins, including those deleted.
#  This is a text filter to remove those deleted.  Requires 3 states:
#
#  $delete
#     0     Pass the line
#     1     Delete current line
#     2     Delete until next subject sequence
#
sub remove_deleted_fids
{
    my $fig = shift;
    my $delete = 0;

    grep { if ( /^(fig\|\d+\.\d+\.[^.]+\.\d+)/ )
           {
               $delete = $fig->is_real_feature( $1 ) ? 0 : 1;
           }
           elsif ( /^>(fig\|\d+\.\d+\.[^.]+\.\d+)/ )
           {
               $delete = $fig->is_real_feature( $1 ) ? 0 : 2;
           }
           elsif ( $delete == 1 )     # Deleted 1 previous line
           {
               $delete = 0;
           }
           elsif ( /^ +Database: / )  # No more subject sequences
           {
               $delete = 0;
           }
           ! $delete            # If we don't want to delete, pass the line
         } @_;
}


sub execute_blastall
{
    my( $prog, $input, $db, @opts ) = @_;

    my $blastall = "$FIG_Config::ext_bin/blastall";
    @opts = split " ", $opts[0]  if @opts == 1 && $opts[0] && $opts[0] =~ /\s/;
    my @args = ( -p => $prog,
                 -i => $input,
                 -d => $db,
                 -a => 4,
                 @opts
               );

    open( BLAST, "-|", $blastall, @args ) or die join( " ", $blastall, @args, "failed: $!" );
    my @out = <BLAST>;
    close BLAST;

    wantarray ? @out : join( '', @out );
}


#
#     @hsps = execute_blast( $blast_prog, $query, $db, @opts )
#    \@hsps = execute_blast( $blast_prog, $query, $db, @opts )
#
#     $blast_prog is one of the set { blastp, blastn, blastx, tblastn }
#     $query is a sequence ([id, def, seq]), a list of sequences, or a
#          sequence file name
#     $db is a sequence ([id, def, seq]), a list of sequences, or a
#          sequence file name
#     @opts is one or more stings with blastall options
#
sub execute_blast
{
    my( $blast_prog, $query, $db ) = splice @_, 0, 3;

    my $opts = { threads =>  4,
                 outForm => 'hsp'
               };

    $opts = blastall_opt_to_opthash( $opts, @_ );

    my $hsps = BlastInterface::blast( $query, $db, $blast_prog, $opts );

    wantarray ? @$hsps : $hsps;
}


sub blastall_opt_to_opthash
{
    my $opts = @_ && $_[0] && ref($_[0]) eq 'HASH' ? shift : {};

    my @opts = ( @_ == 1 && $_[0] && $_[0] =~ /\s/) ? split " ", $_[0] : @_;
    @opts = map { /^(-\S)\s*(\S.*)$/ ? ( $1, $2 ) : $_ } @opts;

    while ( ( @opts > 1 ) && ( ($opts[0] || '') =~ /^-\S$/ ) )
    {
        my ( $flag, $val ) = splice @opts, 0, 2;
        if    ( $flag eq '-D' ) { $opts->{ dbCode }          = $val }
        elsif ( $flag eq '-Q' ) { $opts->{ queryCode }       = $val }
        elsif ( $flag eq '-L' ) { $opts->{ queryLoc }        = $val }
        elsif ( $flag eq '-F' ) { $opts->{ lcFilter }        = $val }
        elsif ( $flag eq '-U' ) { $opts->{ caseFilter }      = $val }
        elsif ( $flag eq '-e' ) { $opts->{ maxE }            = $val }
        elsif ( $flag eq '-b' ) { $opts->{ maxHSP }          = $val }
        elsif ( $flag eq '-v' ) { $opts->{ maxHSP }          = $val }
        elsif ( $flag eq '-M' ) { $opts->{ matrix }          = $val }
        elsif ( $flag eq '-r' ) { $opts->{ nucIdenScr }      = $val }
        elsif ( $flag eq '-q' ) { $opts->{ nucMisScr }       = $val }
        elsif ( $flag eq '-g' ) { $opts->{ ungapped }        = $val }
        elsif ( $flag eq '-t' ) { $opts->{ maxIntronLength } = $val }
        else
        {
            print STDERR "Ignoring user-supplied blast option: '$flag $val'\n";
        }
    }

    $opts;
}


#  Changed to:
#     Include low complexity filter in blast search.
#     Remove all but first match to a given database sequence.
#     Sort by bit-score, not E-value (which becomes equal for all strong matches).
#     Limit to 1000 matches.
#  -- GJO

sub blast_complete
{
    my( $fig, $cgi, $html, $seqfile, $query, $seq ) = @_;
    eval { require Sim; require SimsTable; };

    my $max_e_val    =    0.01;
    my $max_per_subj =    3;
    my $max_per_gen  =  100;
    my $max_sims     = 1000;

    my @sims = ();
    my ( $db ) = grep { -s $_ } (  $FIG_Config::seed_genome_nr,
                                  "$FIG_Config::global/seed.nr"
                                );
    if ( $db && BlastInterface::verify_db( $db, "p" ) )
    {
        my $blast_opt = { maxE        => $max_e_val,
                          lcFilter    =>        'T', # low complexity filter
                          softMasking =>          1, # filter initial screen only
                          maxHSP      =>  $max_sims,
                          outForm     =>      'sim',
                          threads     =>          4,
                          blastplus   =>          1
                        };
        my $sim;
        my %seen = ();
        my @md5_sims = grep { ++$seen{ $_->id2 } <= $max_per_subj }
                       sort { $b->bsc <=> $a->bsc }
                       BlastInterface::blast( $seqfile, $db, 'blastp', $blast_opt );
        foreach my $md5_sim ( @md5_sims )
        {
            #  Expand md5 to fids
            push @sims, map  { my $sim = [ @$md5_sim ];  # copy
                               $sim->[1] = $_;           # fix id
                               Sim->new( $sim )          # bless it
                             }
                        grep { $fig->is_real_feature( $_ ) }
                        $fig->pegs_with_md5( $md5_sim->id2 );

            last if @sims >= $max_sims;
        }
    }
    else
    {
        my $blast_opt = { maxE     =>   $max_e_val,
                          lcFilter =>          'T',
                          maxHSP   => $max_per_gen,
                          outForm  =>        'sim',
                          threads  =>            4
                        };

        foreach my $genome ( $fig->genomes("complete") )
        {
            my $db = "$FIG_Config::organisms/$genome/Features/peg/fasta";
            next if ( ! -s $db );
            next if ( ! BlastInterface::verify_db( $db, "p" ) );

            my %seen = ();  # Limit hits per subject sequence
            push @sims, map { ( ++$seen{ $_->id2 } > $max_per_subj ) ? () : $_ }
                        BlastInterface::blast( $seqfile, $db, 'blastp', $blast_opt );
        }

        @sims = sort { $b->bsc <=> $a->bsc } @sims;
        splice @sims, $max_sims  if @sims > $max_sims;
    }

    &format_sims( $fig, $cgi, $html, \@sims, $query );
}


#------------------------------------------------------------------------------
#  Graphically display search results on contigs
#
#  use FIGjs        qw( toolTipScript );
#  use GenoGraphics qw( render );
#------------------------------------------------------------------------------

#  Fields produced by next_blast_hsp:
#
#  0   1    2    3   4    5    6    7    8    9    10    11   12    13   14  15 16  17  18 19  20
# qid qdef qlen sid sdef slen scr e_val p_n p_val n_mat n_id n_pos n_gap dir q1 q2 qseq s1 s2 sseq
#------------------------------------------------------------------------------

sub blast_graphics
{
    my ( $fig_or_sprout, $cgi, $genome, $hsps, $tool ) = @_;

    my $e_min = 0.1;
    my $gg = [];
    my @html = ();

    foreach ( @$hsps )
    {
        my ( $qid, $qlen, $contig, $slen ) = @$_[0, 2, 3, 5 ];
        my ( $e_val, $n_mat, $n_id, $q1, $q2, $s1, $s2 ) = @$_[ 7, 10, 11, 15, 16, 18, 19 ];
        next if $e_val > $e_min;
        my ( $genes, $min, $max ) = hsp_context( $fig_or_sprout, $cgi, $genome,
                                                 $e_val, 100 * $n_id / $n_mat,
                                                 $qid,    $q1, $q2, $qlen,
                                                 $contig, $s1, $s2, $slen
                                               );
        if ($min && $max)
        {
            push @$gg, [ substr( $contig, 0, 18 ), $min, $max, $genes ];
        }
    }

    # $gene  = [ $beg, $end, $shape, $color, $text, $url, $pop-up, $alt_action, $pop-up_title ];
    # $genes = [ $gene, $gene, ... ];
    # $map   = [ $label, $min_coord, $max_coord, $genes ];
    # $gg    = [ $map, $map, ... ];
    # render( $gg, $width, $obj_half_heigth, $save, $img_index_number )

    if ( @$gg )
    {
        # print STDERR Dumper( $gg );
        my $space = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;";
        my $legend = "<TABLE>\n"
                   . "    <TR>\n"
                   . "        <TD>Q = Query sequence$space</TD>\n"
                   . "        <TD Bgcolor='#FF0000'>$space</TD><TD>Frame 1 translation$space</TD>\n"
                   . "        <TD Bgcolor='#00FF00'>$space</TD><TD>Frame 2 translation$space</TD>\n"
                   . "        <TD Bgcolor='#0000FF'>$space</TD><TD>Frame 3 translation$space</TD>\n"
                   . "        <TD Bgcolor='#808080'>$space</TD><TD>Untranslated feature</TD>\n"
                   . "    </TR>\n"
                   . "</TABLE><P />";

        push @html, "\n", FIGjs::toolTipScript(), "\n",
                    $legend,
                    @{ GenoGraphics::render( $gg, 600, 4, 0, 1 ) },
                    $cgi->hr, "\n";
    }

    return @html;
}


sub hsp_context {
    my( $fig_or_sprout, $cgi, $genome, $e_val, $pct_id,
        $qid,    $q1, $q2, $qlen,
        $contig, $s1, $s2, $slen ) = @_;
    my $half_sz = 5000;

    my( $from, $to, $features, $fid, $beg, $end );
    my( $link, $lbl, $ftrtype, $function, $uniprot, $info, $prot_query );

    my $user   = $cgi->param( 'user' ) || "";
    my $sprout = $cgi->param( 'SPROUT' ) ? '&SPROUT=1' : '';

    my @genes  = ();

    #  Based on the match position of the query, select the context region:

    ( $from, $to ) = ( $s1 <= $s2 ) ? ( $s1 - $half_sz, $s2 + $half_sz )
                                    : ( $s2 - $half_sz, $s1 + $half_sz );
    $from = 1      if ( $from < 1 );
    $to   = $slen  if ( $to > $slen );

    #  Get the genes in the region, and adjust the ends to include whole genes:

    ( $features, $from, $to ) = genes_in_region( $fig_or_sprout, $cgi, $genome, $contig, $from, $to );

    #  Fix the end points if features have moved them to exclude query:

    if ( $s1 < $s2 ) { $from = $s1 if $s1 < $from; $to = $s2 if $s2 > $to }
    else             { $from = $s2 if $s2 < $from; $to = $s1 if $s1 > $to }

    #  Add the other features:

    foreach $fid ( @$features )
    {
        my $contig1;
        ( $contig1, $beg, $end ) = boundaries_of( $fig_or_sprout, feature_locationS( $fig_or_sprout, $fid ) );
        next if $contig1 ne $contig;

        $link = "";
        if ( ( $lbl ) = $fid =~ /peg\.(\d+)$/ )
        {
            $link = "$FIG_Config::cgi_url/protein.cgi?prot=$fid&user=$user";
            $ftrtype = 'peg';
        }
        elsif ( my ( $type ) = $fid =~ /^fig\|\d+\.\d+\.([a-z]+)\.\d+$/ )
        {
            $link = "$FIG_Config::cgi_url/feature.cgi?feature=$fid&user=$user";
            $lbl = uc $type;
            $ftrtype = $type;
        }
        else
        {
            $lbl = "";
            $ftrtype = '';
        }

        $function = function_ofS( $fig_or_sprout, $fid );

        $uniprot = join ", ", grep { /^uni\|/ } feature_aliasesL( $fig_or_sprout, $fid );

        $info = join( '<br />', "<b>Feature:</b> $fid",
                                "<b>Contig:</b> $contig",
                                "<b>Begin:</b> $beg",
                                "<b>End:</b> $end",
                                $function ? "<b>Function:</b> $function" : '',
                                $uniprot ? "<b>Uniprot ID:</b> $uniprot" : ''
                    );

        # $gene  = [ $beg, $end, $shape, $color, $text, $url, $pop-up, $alt_action, $pop-up_title ];

        push @genes, [ feature_graphic( $beg, $end, $ftrtype ),
                       $lbl, $link, $info,
                       $ftrtype eq 'peg' ? () : ( undef, "Feature information" )
                     ];
    }

    #  Draw the query.  The subject coordinates are always DNA.  If the query
    #  is protein, it is about 3 times shorter than the matching contig DNA.
    #  Splitting the difference, if 1.7 times the query length is still less
    #  than the subject length, we will call it a protein query (and reading
    #  frame in the contig coordinates has meaning).  If it is nucleotides,
    #  there is no defined frame.

    $info = join( '<br />', $qid ne 'query ' ? "<b>Query:</b> $qid" : (),
                            "<b>Length:</b> $qlen",
                            "<b>E-value:</b> $e_val",
                            "<b>% identity:</b> " . sprintf( "%.1f", $pct_id ),
                            "<b>Region of similarity:</b> $q1 &#150; $q2"
                );
    $prot_query = ( 1.7 * abs( $q2 - $q1 ) < abs( $s2 - $s1 ) ) ? 1 : 0;

    if ( $user && $prot_query )
    {
        $link = "$FIG_Config::cgi_url/propose_new_peg.cgi?user=$user&genome=$genome&covering=${contig}_${s1}_${s2}";
    }
    else
    {
        $link = undef;
    }

    push @genes, [ feature_graphic( $s1, $s2, $prot_query ? 'peg' : 'rna' ),
                   'Q', $link, $info, undef, 'Query and match information'
                 ];

    return \@genes, $from, $to;
}


sub feature_graphic {
    my ( $beg, $end, $ftrtype ) = @_;

    my $fwd = $beg <= $end;
    my ( $min, $max ) = $fwd ? ( $beg, $end ) : ( $end, $beg );
    my $symb = $ftrtype eq 'peg' ? ( $fwd ? 'rightArrow' : 'leftArrow' )
             : $ftrtype eq 'rna' ? ( $fwd ? 'topArrow'   : 'bottomArrow' )
             :                     'Rectangle';

    #  Color proteins by translation frame

    my $color = $ftrtype eq 'peg' ? qw( blue red green )[ $beg % 3 ] : 'grey';

    ( $min, $max, $symb, $color );
}


sub genes_in_region {
    my( $fig_or_sprout, $cgi, $genome, $contig, $min, $max ) = @_;

    if ( $cgi->param( 'SPROUT' ) )
    {
        my( $x, $feature_id );
        my( $feat, $min, $max ) = $fig_or_sprout->genes_in_region( $genome, $contig, $min, $max );
        my @tmp = sort { ($a->[1] cmp $b->[1]) or
                         (($a->[2]+$a->[3]) <=> ($b->[2]+$b->[3]))
                       }
                  map  { $feature_id = $_;
                         $x = feature_locationS( $fig_or_sprout, $feature_id );
                         $x ? [ $feature_id, boundaries_of( $fig_or_sprout, $x )]  : ()
                       }
                  @$feat;
        return ( [map { $_->[0] } @tmp ], $min, $max );
    }
    else
    {
        return $fig_or_sprout->genes_in_region( $genome, $contig, $min, $max );
    }
}


sub feature_locationS {
    my ( $fig_or_sprout, $peg ) = @_;
    scalar $fig_or_sprout->feature_location( $peg );
}


sub boundaries_of {
    my( $fig_or_sprout, $loc ) = @_;
    $fig_or_sprout->boundaries_of( $loc );
}


sub function_ofS {
    my( $fig_or_sprout, $peg, $user ) = @_;
    scalar $fig_or_sprout->function_of( $peg, $user );
}


sub feature_aliasesL {
    my( $fig_or_sprout, $fid ) = @_;
    my @tmp = $fig_or_sprout->feature_aliases( $fid );
    @tmp
}


#
#  -m 8 output field definitions:
#
#   0   id1         query sequence id
#   1   id2         subject sequence id
#   2   iden        percentage sequence identity
#   3   ali_ln      alignment length
#   4   mismatches  number of mismatch
#   5   gaps        number of gaps
#   6   b1          query seq match start
#   7   e1          query seq match end
#   8   b2          subject seq match start
#   9   e2          subject seq match end
#  10   psc         match e-value
#  11   bsc         bit score
#
#  Added columns in Sim object:
#
#  12   ln1         query length
#  13   ln2         subject length
#
sub format_sims
{
    my( $fig, $cgi, $html, $sims, $query, $opts ) = @_;
    if ( @$sims )
    {
        push @$html, "<H3>SEED sequences similar to '$query'</H3>\n";
        my @cols = qw( checked s_id e_val/identity s_region q_region from s_subsys s_evidence s_def s_genome );
        $opts = {} unless $opts && ( ref $opts eq 'HASH' );
        $opts->{ col_request } = \@cols;
        push @$html, SimsTable::similarities_table( $fig, $cgi, $sims, '', $opts );
    }
    else
    {
        push @$html, "<H3>No sequences similar to '$query' where found</H3>\n";
    }
}


sub export_assignments {
    my($fig,$cgi,$html,$who) = @_;
    my($genome,$x);

    my @genomes = map { $_ =~ /(\d+\.\d+)/; $1 } $cgi->param('korgs');

    if (@genomes == 0)
    {
        @genomes = $fig->genomes;
    }

    my @assignments = $fig->assignments_made(\@genomes,$who,$cgi->param('after_date'));
    if (@assignments == 0)
    {
        push(@$html,$cgi->h1("Sorry, no assignments where made by $who"));
    }
    else
    {
        my $col_hdrs = ["FIG id", "External ID", "Genus/Species","Assignment"];
        my $tab = [];
        my($x,$peg,$func);
        foreach $x (@assignments)
        {
            ( $peg, $func ) = @$x;
            push( @$tab,[ HTML::set_prot_links( $cgi, $peg ),
                          HTML::set_prot_links( $cgi, ext_id( $fig, $peg ) ),
                          $fig->genus_species($fig->genome_of($peg)),
                          $func
                        ] );
        }

        if ($cgi->param('save_assignments'))
        {
            my $user = $cgi->param('save_user');
            if ($user)
            {
                &FIG::verify_dir("$FIG_Config::data/Assignments/$user");
                my $file = &FIG::epoch_to_readable(time) . ":$who:exported_from_local_SEED";
                if (open(TMP,">$FIG_Config::data/Assignments/$user/$file"))
                {
                    print TMP join("",map { join("\t",@$_) . "\n" } map { [$_->[0],$_->[3]] } @$tab);
                    close(TMP);
                }
                push(@$html,$cgi->h1("Saved Assignment Set $file"));
            }
            else
            {
                push(@$html,$cgi->h1("You need to specify a user to save an assignment set"));
            }
        }

        if ($cgi->param('tabs'))
        {
            print $cgi->header;
            print "<pre>\n";
            print join("",map { join("\t",@$_) . "\n" } @$tab);
            print "</pre>\n";
            &done;
        }
        else
        {
            push(@$html,&HTML::make_table($col_hdrs,$tab,"Assignments Made by $who"));
        }
    }
}

sub ext_id {
    my($fig,$peg) = @_;

    my @mapped = grep { $_ !~ /^fig/ } map { $_->[0] } $fig->mapped_prot_ids($peg);
    if (@mapped == 0)
    {
        return $peg;
    }

    my @tmp = ();
    if ((@tmp = grep { $_ =~ /^sp/ }   @mapped) && (@tmp > 0))  { return $tmp[0] }
    if ((@tmp = grep { $_ =~ /^pir/ }  @mapped) && (@tmp > 0))  { return $tmp[0] }
    if ((@tmp = grep { $_ =~ /^gi/ }   @mapped) && (@tmp > 0))  { return $tmp[0] }
    if ((@tmp = grep { $_ =~ /^tr/ }   @mapped) && (@tmp > 0))  { return $tmp[0] }
    if ((@tmp = grep { $_ =~ /^tn/ }   @mapped) && (@tmp > 0))  { return $tmp[0] }
    if ((@tmp = grep { $_ =~ /^kegg/ } @mapped) && (@tmp > 0))  { return $tmp[0] }

    return $peg;
}

sub translate_assignments {
    my($fig,$cgi,$html,$from_func,$to_func) = @_;

    my @funcs = grep { $_ =~ /^\S.*\S$/ } split(/[\012\015]+/,$from_func);

    my $user = $cgi->param('save_user');
    if ($user)
    {
        &FIG::verify_dir("$FIG_Config::data/Assignments/$user");
        my $file = &FIG::epoch_to_readable(time) . ":$user:translation";
        if (open(TMP,">$FIG_Config::data/Assignments/$user/$file"))
        {
            my($peg,$func);

            foreach $from_func (@funcs)
            {
                my $from_funcQ = quotemeta $from_func;

                foreach $peg ($fig->seqs_with_role($from_func))
                {
                    if ($peg =~ /^fig\|/)
                    {
                        $func = $fig->function_of($peg);
                        my $comment = "";
                        if ($func =~ /^([^\#]*)(\#.*)$/)
                        {
                            $comment = $2;
                            $func = $1;
                            $func =~ s/\s+$//;
                            $comment = $comment ? " $comment" : "";
                        }

                        if ($func eq $from_func)
                        {
                            print TMP "$peg\t$to_func$comment\n";
                        }
                        else
                        {
                            my @pieces = grep { $_ } split(/(\s+[\/@]\s+)|(\s*;\s+)/,$func);
                            if (@pieces > 1)
                            {
                                my $func1 = join("",map { $_ =~ s/^$from_funcQ$/$to_func/; $_ } @pieces);
                                if ($func ne $func1)
                                {
                                    print TMP "$peg\t$func1$comment\n";
                                }
                            }
                        }
                    }
                }
            }
            close(TMP);
        }
        push(@$html,$cgi->h1("Saved Assignment Set $file"));
    }
    else
    {
        push(@$html,$cgi->h1("You need to specify a user to save an assignment set"));
    }
}

sub find_pegs_by_cv1 {
    my ($fig, $cgi, $html, $user, $pattern, $cv) = @_;

    # Remember kind of search that got us hear so we can call back
    # with same kind
    my $search = "Search";
    if ($cgi->param('Search genome selected below')) {
        $search=uri_escape('Search genome selected below');
    } elsif ( $cgi->param('Search Selected Organisms') )  {
        $search = uri_escape('Search Selected Organisms');
    } elsif ( $cgi->param('Find Genes in Org that Might Play the Role') ) {
        $search = uri_escape('Find Genes in Org that Might Play the Role');
    }

    my $search_results = $fig->search_cv_file($cv, $pattern);

    my $find_col_hdrs = ["Find","Vocab. Name","ID; Term"];
    my $find_table_rows;
    my $counter = 0;
    for my $r (@$search_results)
    {
        my @temp = split("\t",$r);
        my $row = [];
        my $id= $temp[1];
        my $term = $temp[2];
        my $id_and_term = $id."; ".$term;
        my $pattern=uri_escape("$id; $term");

        my $link = "$FIG_Config::cgi_url/index.cgi?pattern=$pattern&Search=1&user=$user";
        my $cb = "<a href=$link>Find PEGs</a>";

        #feh my $cb = $cgi->submit(-name=>'$search', -value=>'Find PEGs');
        #my $cb_value = $cv."split_here".$id."; ".$term;
        #my $cb ="<input type=checkbox name=find_checked_$counter value='$cb_value'>" ;
        push(@$row,$cb);
        push(@$row,$cv);
        push(@$row,$id_and_term);
        push(@$find_table_rows,$row);
        $counter = $counter + 1;
    }

    my $find_terms_button="";
    if ($counter > 0) {
        $find_terms_button= $cgi->submit(-name=>'$search', -value=>'$search');
    }

    # build the page
    push @$html,
    $cgi->start_form(),
    $cgi->hidden(-name=>'user', -value=>'$user'),
    $cgi->br,
    "<h2>Search for PEGs annotated with Contrlled Vocabulary Terms</h2>",
    $cgi->hr,
    "<h4>Terms Matching Your Criteria </h4>\n",
    $cgi->br,
    &HTML::make_table($find_col_hdrs,$find_table_rows),
    $cgi->br,
    $find_terms_button,
    $cgi->end_form;

    return $html;
}

sub find_pegs_by_cv {
    my ($fig, $cgi, $html, $user, $pattern, $cv) = @_;

    # Remember kind of search that got us hear so we can call back
    # with same kind  (not working so force to simple Search)

    my $search = "Search";

    #if ($cgi->param('Search genome selected below')) {
    #        $search='Search genome selected below';
    #} elsif ( $cgi->param('Search Selected Organisms') )  {
    #        $search = 'Search Selected Organisms';
    #} elsif ( $cgi->param('Find Genes in Org that Might Play the Role') ) {
    #    $search = 'Find Genes in Org that Might Play the Role';
    #}

    my $search_results = $fig->search_cv_file($cv, $pattern);

    my $find_col_hdrs = ["Find","Vocab. Name","ID; Term"];
    my @patterns=();
    for my $r (@$search_results)
    {
        my @temp = split("\t",$r);
        my $id= $temp[1];
        my $term = $temp[2];
        my $pattern="$id; $term";

        push(@patterns,$pattern);
    }

    my @pattern_radio;
    if ($#patterns + 1) {
        @pattern_radio = $cgi->radio_group( -name     => 'pattern',
                                               -values   => [ @patterns ]
                                               );
    } else {
        @pattern_radio = ("Nothing found");
    }

    my $find_terms_button= $cgi->submit(-name=>"Search", -value=>"Search");

    # build the page
    push @$html,
    $cgi->start_form(),
    $cgi->hidden(-name=>'user', -value=>'$user'),
    $cgi->br,
    "<h2>Search for PEGs annotated with Contrlled Vocabulary Terms</h2>",
    $cgi->hr,
    "<h4>$cv Terms Matching Your Criteria </h4>\n",
    $cgi->br,
    $find_terms_button,
    $cgi->br,
    $cgi->br,
    join( "<br>", @pattern_radio),
#    &HTML::make_table($find_col_hdrs,$find_table_rows),
    $cgi->br,
    $find_terms_button,
    $cgi->end_form;

    return $html;
}
