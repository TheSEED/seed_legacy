package WebApplicationComponents::Tabulator;

use strict;
use warnings;

1;

sub new {
  my ($classname, $params) = @_;

  # get params
  my $id = $params->{id} || "tabulator";
  my $tabs = $params->{tabs};
  my $initially_active_tab = $params->{initially_active_tab} || 0;
  my $tabwidth = $params->{tabwidth} || 80;
  my $tabheight = $params->{tabheight} || 18;
  my $width = $params->{width} || undef;
  my $height = $params->{height} || 500;
  my $numtabs = scalar(@$tabs);

  # initialize html-string
  my $tabulator = qq~<div style="height: ~ . $height . qq~px; overflow: hidden;"><table class="tabulator_table" style="height: ~ . $tabheight . qq~px;"><tr>~;

  # initialize content string
  my $content = "";

  # draw tab-headers
  my $tabnum = 0;
  unless (defined($width)) {
    $width = "";
  }
  foreach my $tab (@$tabs) {
    my $class_header = "tabulator_select_back";
    my $z_index = 1;
    if ($tabnum == $initially_active_tab) {
      $class_header = "tabulator_select_front";
      $z_index = 2;
    }
    $tabulator .= qq~<td name="tabulator_~ . $id . qq~_select" class="~ . $class_header . qq~" onclick="activate_tab('~ . $id . qq~', '~ . $tabnum . qq~');" style="width: ~ . $tabwidth . qq~px;">~ . $tab->[0] . qq~</td>~;

    $content .= qq~<div class="tabulator_content" name="tabulator_~ . $id . qq~_body" style="z-index: ~ . $z_index . qq~; top: ~ . ($tabnum * -1 * ($height + 1)) . qq~px;~ . $width . qq~ height: ~ . $height . qq~px; position: relative;">~ . $tab->[1] . qq~</div>~;

    $tabnum++;
  }

  # draw tab-header buffer
  $tabulator .= qq~<td class="tabulator_spacer"></td>~;

  # close header table
  $tabulator .= qq~</tr></table>~;

  # draw tab-bodies
  $tabulator .= $content;

  # end surrounding div
  $tabulator .= "</div>";

  return $tabulator;
}
