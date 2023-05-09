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

package FIGjs;
use FIG;
use strict;

=pod

=head1 FIGjs javascript package. delivers links and creates HTML code for mouseover info

usage: mouseover($title, $info, $menu)

creates a tooltip with title = $title and $info <HTML text>
can be plugged in to any html 
example 

push(@$html,"<area shape=\"rect\" coords=\"$coords\" href=\"$link\" ".&FIGjs::mouseover( "Peg info", $object->[6]).">\n");

=cut

# Note that the actual script has now been put into FigCSS/FIG.js
# this contains several javascript methods, separates them from the html,
# and keeps things cleaner this method is here because it is almost certainly
# being called in places I have missed.
# RAE

sub toolTipScript {
    #  my $url = &FIG::cgi_url() . "/Html/css/FIG.js";
    #  Changed to relative URL -- GJO

    my $url = "$FIG_Config::cgi_url/Html/css/FIG.js";
    qq(<script language="JavaScript" type="text/javascript" src="$url"></script>);
}


#  Cleaned, simplified and commented -- GJO

=head2 mouseover()

Generate a mouseover for your code.

You can use it like this: 
push @$html, "<a " . FIGjs::mouseover("Title", "Body Text", "Menu", $parent, $title_bg_color, $text_bg_color) . " href='link.cgi'>a link</a>";

and the appropriate javascript will be added for you.

Title: The title of the popup that appears in bold
Body Text: The text to appear in the box.
Menu: This is probably the alternate menu that appears on the pinned regions page??

Please note these should be HTML code so <b>text</b> will appear as bold. Also, please don't put linebreaks in the text since that breaks everything.
The text strings supplied must already be HTML escaped (< or & will be treated as HTML, not text). 

$parent is whether to place the box under the cursor or elsewhere on the page (e.g. top right corner)
Please note that there is an error at the moment and the value of parent doesn't affect anything. 
Note also that I (RAE) didn't add this, but I have left it here for compatability with mouseover calls that expect it to be here.

$title_bg_color is the color of the background for the title. The default blue color is #333399. Please include the # in describing the color
$text_bg_color is the color of the body of the text. The default body color is #CCCCFF. Please include the # in describing the color

You don't need to supply the default colors, but can make the box red or green if you like.

=cut


sub mouseover {
    my ($title, $text, $menu, $parent, $hc, $bc) = @_;

    defined( $title ) or $title = '';
    $title =~ s/'/\\'/g;    # escape '
    $title =~ s/"/&quot;/g; # escape "

    #  Fixed incorrect quoting of $text (reversed single and double quote)
    #  -- GJO

    defined( $text ) or $text = '';
    $text =~ s/'/\\'/g;    # escape '
    $text =~ s/"/&quot;/g; # escape "

    defined( $menu ) or $menu = '';
    $menu =~ s/'/\\'/g;    # escape '
    $menu =~ s/"/&quot;/g; # escape "

    qq( onMouseover="javascript:if(!this.tooltip) this.tooltip=new Popup_Tooltip(this,'$title','$text','$menu','$parent','$hc','$bc');this.tooltip.addHandler(); return false;" );
}


#  I'm not sure that this exists -- GJO
#  I agree, and I don't think it is ever called. I have added a die statement on 11/17/2005, feel free to delete this
#  if it has been a while and no one has complained about things dying -- Rob

sub toolTipLink {
    die "toolTipLink was called. Please email this error to Rob (RobE\@thefig.info). Sorry\n";
    return '<script src="Html/popup_tooltip.js" type="text/javascript"></script>';
}


sub setValueScript {
return <<'SCRIPT';
<script type="text/javascript">
function setValue(id, val) {
   var element = document.getElementById(id);
   element.value = val;
}
</script>    
SCRIPT
}

1;
