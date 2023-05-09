#!/usr/bin/perl -w

# -*- perl -*-
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

package TemplateObject;

    use strict;
    use Tracer;
    use PageBuilder;
    use FIG_CGI;
    use SeedComponents::Framework;

=head1 Template Object Manager

=head2 Introduction

The template object manager is used to build HTML in the presence or absence of a
template. The constructor looks for a template and remembers whether or not
it found one. To add HTML to the object, you call the L</add> method with a
variable name and the HTML to add. The example below puts the results of
the C<build_html> method into the template C<$to> with the name C<frog>.

    $to->add(frog => build_html($thing));

Once all the HTML is added, you call finish to generate the web page.

    print $to->finish();

If no template exists, the HTML will be output in the order in which
it was added to the template object. If a template does exist, the
HTML assigned to each name will be substituted for the variable with
that name.

Sometimes extra text is needed in raw mode. If you code

    $to->add($text);

the text is discarded in template mode and accumulated in raw mode. If
you're doing complicated computation, you can get a faster result using
an IF construct.

    $to->add(build_html($data)) if $to->raw;

This bypasses the call to C<build_html> unless it is necessary.

The template facility used is the PERL C<HTML::Template> facility, so
anything that follows the format of that facility will work. The
most common use of the facility is simple variable substition. In
the fragment below, the variable is named C<topic>.

    <p>This page tells how to do <TMPL_VAR NAME=TOPIC>.

If the following call was made at some point prior to finishing

    $to->add(topic => "subsystem annotation");

The result would be

    <p>This page tells how to do subsystem annotation.

Almost all templates are stored in files. Some are stored in the server's
file system and some are stored on remote servers. Regardless of the
location, a template file name consists of a base name, a type, and
a request code. If no request code is specified, the template name
is I<base>C<_tmpl.>I<type>. If a request code is specified, the template name is
I<base>C<_tmpl_>I<request>C<.>I<type>. This allows the templates to
be tailored to different versions of the calling script.

The following constructor starts the template for the protein page.

    my $to = TemplateObject->new($cgi, php => 'Protein', $cgi->param('request'));

If the CGI object indicates Sprout is active, the template object will look
for a template file at the C<$FIG_Config::template_url> directory. If no
template URL is specified, it will look for the template file in the
C<$FIG_Config::fig/CGI/Html> directory. The template file is presumed to have
a type suffix of C<php>. If the template is coming from a web server, any
include files or other PHP commands will already have been executed by the time
the file reaches us. If the template is coming from the file system, the
suffix has no operational effect: the template file is read in unaltered.

=cut

#: Constructor TemplateObject->new();

=head2 Public Methods

=head3 new

    my $to = FIG_CGI->new($cgi, $type => $name, $request);

Construct a new template object for the current script.

Currently, only Sprout uses templates.

A template name consists of a base, a type, and a request code. If no
request code is specified, the template name is I<base>C<_tmpl.>I<type>.
If a request code is specified, the template name is
I<base>C<_tmpl_>I<request>C<.>I<type>. This allows the templates to be
tailored to different versions of the calling script.

=over 4

=item cgi

CGI object for the current script.

=item type

Template type, usually either C<php> or C<html>. The template type is used as
the file name suffix.

=item name

Base name of the template.

=item request (optional)

Request code for the script. If specified, the request code is joined to the
base name to compute the template name.

=back

=cut

sub new {
    # Get the parameters.
    my ($class, $cgi, $type, $name, $request) = @_;
    # Declare the template name variable.
    my $template = "";
    # Check for Sprout mode.
    if (is_sprout($cgi)) {
        # Here we're in Sprout, so we have a template. First, we compute
        # the template name.
        my $requestPart = ($request ? "_$request" : "");
        $template = "${name}_tmpl$requestPart.$type";
        # Now we need to determine the template type and prefix the source location
        # onto it.
        if ($FIG_Config::template_url) {
            $template = "$FIG_Config::template_url/$template";
        } else {
            $template = "<<$FIG_Config::fig/CGI/Html/$template";
        }
    }
    # Now $template is either a null string (FALSE) or the name of the
    # template (TRUE). We are ready to create the return object.
    my $retVal = { template => $template,
                   cgi => $cgi,
                 };
    # Next we add the object that will be accepting the HTML strings.
    if ($template) {
        $retVal->{varHash} = {};
    } else {
        $retVal->{html} = [];
    }
    # Return the result.
    bless $retVal, $class;
    return $retVal;
}

=head3 mode

    my $flag = $to->mode();

Return TRUE if a template is active, else FALSE.

=cut

sub mode {
    # Get the parameters.
    my ($self) = @_;
    # Return the result.
    return ($self->{template} ? 1 : 0);
}

=head3 raw

    my $flag = $to->raw();

Return TRUE if we're accumulating raw HTML, else FALSE.

=cut

sub raw {
    # Get the parameters.
    my ($self) = @_;
    # Return the result.
    return ($self->{template} ? 0 : 1);
}

=head3 add

    $to->add($name => $html);

or

    $to->add($html);

Add HTML to the template data using the specified name. If a template is in effect, the
data will be put into a variable hash. If raw HTML is being accumulated, the data will
be added to the end of the HTML list. In the second form (without the name), the
text is discarded in template mode and added to the HTML in raw mode.

=over 4

=item name (optional)

Name of the variable to be replaced by the specified HTML. If omitted, the HTML is
discarded if we are in template mode.

=item html

HTML string to be put into the output stream. Note that if it is guaranteed that a template
is to be used, references to lists of text or hashes may also be passed in, depending on
the features used by the template.

=back

=cut

sub add {
    # Get the parameters.
    my ($self, $name, $html) = @_;
    # Adjust the parameters if no name was specified.
    if (! defined($html)) {
        $html = $name;
        $name = "";
    }
    # Check the mode.
    if ($self->mode) {
        # Here we're using a template. We only proceed if a name was specified.
        if ($name) {
            $self->{varHash}->{$name} = $html;
        }
    } else {
        # No template: we're just accumulating the HTML in a list.
        push @{$self->{html}}, $html;
    }
}

=head3 append

    $to->append($name, $html);

Append HTML to a named variable. Unlike L</add>, this method will not destroy a
variable's existing value; instead, it will concatenate the new data at the end of the
old.

=over 4

=item name

Name of the variable to which the HTML text is to be appended.

=item html

HTML text to append.

=back

=cut

sub append {
    # Get the parameters.
    my ($self, $name, $html) = @_;
    # Check the mode.
    if ($self->mode) {
        # Template mode, so we check for the variable.
        my $hash = $self->{varHash};
        if (exists $hash->{$name}) {
            $hash->{$name} .= $html;
        } else {
            $hash->{$name} = $html;
        }
    } else {
        # Raw mode.
        push @{$self->{html}}, $html;
    }
}

=head3 titles

    to->titles($parameters);

If no template is in use, generate the plain SEED header. If a template is in
use, get the version, peg ID, and message of the day for use in the template.

This subroutine provides a uniform method for starting a web page regardless
of mode.

=over 4

=item parameters

Reference to a hash containing the heading parameters. These are as follows.

=over 8

=item fig_object

Fig-like object used to access the data store.

=item peg_id

ID of the current protein.

=item table_style

Style to use for tables.

=item fig_disk

Directory of the FIG disk.

=item form_target

Target script for most forms.

=back

=back

=cut

sub titles {
    # Get the parameters.
    my ($self, $parameters) = @_;
    my $cgi = $self->{cgi};
    if ($self->{template}) {
        # In template mode, we get useful stuff from the framework. First, the message
        # of the day.
        $self->add(motd => SeedComponents::Framework::get_motd($parameters));
        # Now the version.
        $self->add(version =>
                   SeedComponents::Framework::get_version({fig => $parameters->{fig_object},
                                                                           fig_disk => $parameters->{fig_disk}}));
        # Next, the location tag.
        $self->add(location_tag => $self->{cgi}->url());
        # Finally the protein (if any).
        if (exists $parameters->{peg_id}) {
            $self->add(feature_id => $parameters->{peg_id});
        }
    } else {
      # No template, so we pull in the plain header.
      $self->add("<html><head><title>".$parameters->{title}."</title></head><body>");
      #$self->add($cgi->start_html(-title => $parameters->{title}));
      $self->add(header => SeedComponents::Framework::get_plain_header($parameters));
    }
}

=head3 finish

    my $webPage = $to->finish();

Format the template information into a web page. The HTML passed in by the L</add> methods
is assembled into the proper form and returned to the caller.

=cut

sub finish {
    # Get the parameters.
    my ($self) = @_;
    # Declare the return variable.
    my $retVal;
    # Check the mode.
    if ($self->{template}) {
        # Here we have to process a template.
        $retVal = PageBuilder::Build($self->{template}, $self->{varHash}, "Html");
    } else {
        # Here we need to assemble raw HTML in sequence. First, we check for the
        # closing HTML tags. If the last line is a body close, we only need to add
        # the html close. If it's not a body close or an html close, we need to
        # add both tags.
        my @html = @{$self->{html}};
        if ($html[$#html] =~ m!/body!i) {
            push @html, "</html>";
        } elsif ($html[$#html] !~ m!/html!i) {
            push @html, "</body></html>";
        }
        # Join the lines together to make a page.
        $retVal = join("\n", @html);
    }
    # Return the result.
    return $retVal;
}

1;
