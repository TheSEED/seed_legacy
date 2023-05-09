package WebApplicationComponents::List;

use strict;
use warnings;

1;

sub new {
  my ($class, $params) = @_;

  # retrieve params from params hash
  my @items = @{$params->{items}};
  my @links = [];
  if (defined($params->{links})) {
    @links = @{$params->{links}};
  }
  my $highlight_selected = $params->{highlight_selected} || 0;
  my $show_image = $params->{show_image} || 0;
  my $img_path = $params->{img_path} || "../images/";
  my $headline = $params->{headline} || "";
  my $current = $params->{current} || -1;
  my $id = $params->{id} || "list";

  # determine indirect values
  my $num_items = scalar(@items);

  # initialize list string
  my $list = "<table class='list_table'>";
  
  # check for headline
  if ($headline) {
    $list .= "<tr><td></td><td class='list_headline'>" . $headline . "</td></tr>";
  }

  my $curr = 0;
  foreach my $item (@items) {
    
    my $class_name = "list_item";
    my $image = "";
    my $link = "";

    # check if links are present
    if (defined($links[$curr])) {
      $link = " onclick='list_select(\"list_" . $id . "\", \"" . $links[$curr] . "\")'";
    }

    # check for selected row
    if ($curr == $current) {
      if ($show_image) {
	$image = "<img class='list_image' src='" . $img_path . "arrow.gif'>";
      }
      if ($highlight_selected) {
	$class_name = "list_selected";
      }
    }

    $list .= "<tr><td class='list_img'>" . $image . "</td><td" . $link . " class='" . $class_name . "'>" . $item . "</td></tr>";
    $curr++;
  }

  # close surrounding table
  $list .= "</table>";

  # return list string
  return $list;
}
