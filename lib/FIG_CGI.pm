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


=head1 FIG CGI Script Utility Module

This package contains utility methods for initializing and debugging CGI scripts
in the FIG framework.

=cut

package FIG_CGI;

    require Exporter;
    @ISA = ('Exporter');
    @EXPORT = qw(is_sprout);

=head2 Public Methods

=cut

use strict;
use FIG;
use FIGV;
use FIGM;
use FIG_Config;
use CGI;
use Data::Dumper;
use SproutFIG;
use FIGRules;

use Tracer;

=head3 init

    my($fig, $cgi, $user) = FIG_CGI::init(debug_save => 0, debug_load => 0, print_params => 0);

Initialize a FIG and CGI object for use in the CGI script. Depending on the
CGI parameters passed in, the FIG object will be either an actual FIG object
(when we are in SEED mode), or a SFXlate object (when we are in Sprout mode).

=over 4

=item debug_save

Set this flag to true if the script should save its parameters to a
file. (Default filename is the name of the script minus the .cgi
suffix, placed in the /tmp/ directory).

=item debug_load

Set this flag to true if the script should load its parameters from a
file as saved with debug_save.

=item print_params

Set this flag to true if the script should print its CGI parameters
before exiting.

=item RETURN

Returns a three-tuple. The first element is a FIG or Sprout object. The second
is a CGI object describing the environment of the calling script. The third
is the name of the current user.

=back

=cut

sub init {
    # Get the parameters. The calling syntax uses parameter pairs, so we stash
    # them in a hash.
    my (%args) = @_;
    # Get the CGI and FIG objects.
    my $cgi = new CGI;
    my $fig = init_fig($cgi);
    # Turn on tracing.
    ETracing($cgi);
    # Log this page if it's a robot.
    FIGRules::LogRobot($cgi);
    # If we're debugging, we need to know which file is to receive the debugging
    # information.
    my $script_name = determine_script_name();
    my $file = "/tmp/${script_name}_parms";

    # warn "fig_cgi init $file\n";

    # Check to see if we're supposed to display the parameters. Since "debug_save"
    # mode also prints the parameters, we remember here whether or not we printed
    # them so we don't print them twice.
    my $printed_params;
    if ($args{print_params})
    {
        do_print_params($cgi);
        $printed_params++;
    }

    # Check to see if we're supposed to save the parameters to a debug file or
    # load them from a debug file.
    if ($args{debug_save})
    {
        do_print_params($cgi) unless $printed_params;
        print "Wrote params to $file<p>\n";
        $cgi = do_debug_save($cgi, $file);
    }
    elsif ($args{debug_load})
    {
        $cgi = do_debug_load($cgi, $file);
    }
    # Now the debugging stuff is done and the $cgi object looks exactly the way we
    # want it.

    # Get the user's name.
    my $user = $cgi->param('user') || "";

    return($fig, $cgi, $user);
}

=head3 is_sprout

    my $flag = is_sprout($object);

Return TRUE if we are running in Sprout mode, else FALSE.

=over 4

=item object

FIG, SFXlate, or CGI object. If a FIG object is passed in, the result is always
FALSE. If an SFXlate object is passed in, the result is always TRUE. If a CGI
object is passed in, the value of the C<SPROUT> parameter will be returned.

=item RETURN

Returns TRUE if we're in Sprout mode, else FALSE.

=back

=cut

sub is_sprout {
    # Get the parameters.
    my ($object) = @_;
    # Declare the return variable.
    my $retVal = 0;
    # Check the object type. Note that an unknown object or scalar will
    # default to FALSE. This includes FIG objects, because we don't
    # explicity check for them.
    my $type = ref $object;
    if ($type eq 'SFXlate') {
        $retVal = 1;
    } elsif ($type eq 'CGI') {
        $retVal = FIGRules::nmpdr_mode($object);
    }
    # Return the result.
    return $retVal;
}

sub init_tracing
{
    # DEPRECATED: ETracing is used instead.
}

sub init_fig
{
    my($cgi) = @_;

    my $base_fig;
    my $fig;
    if (FIGRules::nmpdr_mode($cgi))
    {
        $base_fig = new SproutFIG($FIG_Config::sproutDB, $FIG_Config::sproutData);
    }
    else
    {
	$base_fig = new FIG();
    }
    if (my $job = $cgi->param("48hr_job"))
    {
	my $jobdir = "/vol/48-hour/Jobs/$job";
	my $genome = &FIG::file_head("$jobdir/GENOME_ID");
	chomp $genome;
	if ($genome !~ /^\d+\.\d+/)
	{
	    die "Cannnot find genome ID for jobdir $jobdir\n";
	}
	my $orgdir = "$jobdir/rp/$genome";
	if (! -d $orgdir)
	{
	    die "Cannot find orgdir $orgdir\n";
	}
	$fig = new FIGV($orgdir, undef, $base_fig);
    }
    elsif (ref($FIG_Config::figm_dirs) eq 'ARRAY')
    {
	warn "Using FIGM @$FIG_Config::figm_dirs\n";
	$fig = new FIGM($base_fig, @{$FIG_Config::figm_dirs});
    }
    else
    {
	$fig = $base_fig;
    }

    return $fig;
}

sub do_print_params
{
    my($cgi) = @_;

    print $cgi->header;
    my @params = $cgi->param;
    print "<pre>\n";
    foreach $_ (@params) {
        print "$_\t:",join(",",$cgi->param($_)),":\n";
    }
    print "</pre>\n";
}

sub do_debug_load
{
    my($cgi, $file) = @_;
    my $VAR1;
    if (-f $file)
    {
        eval(&FIG::file_read($file));
        $cgi = $VAR1;
    }
    else
    {
        print $cgi->header;
        print "Attempting debug load, but file $file does not exist\n";
        die "Attempting debug load, but file $file does not exist\n";
    }

    return $cgi;
}

sub do_debug_save
{
    my($cgi, $file) = @_;

    if (open(TMP,">$file")) {
        print TMP &Dumper($cgi);
        close(TMP);
        # warn "Loaded cgi from $file\n";
    }
    else
    {
        print $cgi->header;
        print "Attempting debug load, but file $file does not exist\n";
        warn "Attempting debug load, but file $file does not exist\n";
    }
    exit;
}

sub determine_script_name
{
    my $path = $ENV{SCRIPT_NAME};
    my $name;

    if ($path eq '')
    {
        #
        # We're probably being invoked from the command line.
        #

        $path = $0;
    }

    if ($path =~ m,/([^/]+)$,)
    {
        $name = $1;
    }
    else
    {
        $name = $path;
        $name =~ s,/,_,g;
    }
    $name =~ s/\.cgi$//;
    return $name;
}

1;
