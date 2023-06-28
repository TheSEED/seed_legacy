package WebApplicationComponents;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(
		tabulator
		menu
		list
		table
		table2
	       );

use strict;
use warnings;

use WebApplicationComponents::Tabulator;
use WebApplicationComponents::Menu;
use WebApplicationComponents::List;
use WebApplicationComponents::Table;
use WebApplicationComponents::Table2;

sub tabulator {
  my ($params) = @_;

   return WebApplicationComponents::Tabulator->new($params);
}

sub menu {
  my ($params) = @_;

  return WebApplicationComponents::Menu->new($params);
}

sub list {
  my ($params) = @_;

  return WebApplicationComponents::List->new($params);
}

sub table {
  my ($params) = @_;

  return WebApplicationComponents::Table->new($params);
}

sub table2 {
  my ($params) = @_;

  return WebApplicationComponents::Table2->new($params);
}
