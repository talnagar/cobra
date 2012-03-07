#!/usr/bin/perl
use strict;
use Getopt::Long;
use Bio::Phylo::IO 'parse';
use Bio::Phylo::Cobra::TaxaMap;
use Bio::Phylo::Util::Logger ':levels';
use Bio::Phylo::Util::CONSTANT ':objecttypes';
use Data::Dumper;

# process command line arguments
my ( $infile, $format, $csv );
GetOptions(
    'infile=s' => \$infile,
    'format=s' => \$format,
    'csv=s'    => \$csv,
);

# create seen hash for NCBI taxon ids
my $map = Bio::Phylo::Cobra::TaxaMap->new($csv);
my %seen = map { $_ => 1 } $map->get_all_taxonIDs;

# parse tree block from input file
my ($forest) = @{
    parse(
        '-format' => $format,
        '-file'   => $infile,
        '-as_project' => 1,
    )->get_items(_FOREST_)
};

# for each tip in each tree, fetch its taxon object and from that get the
# skos:*match annotations, which may have an NCBI taxon id. if it does,
# copy it over to the tip and taxon name
for my $tree ( @{ $forest->get_entities } ) {
    for my $tip ( @{ $tree->get_terminals } ) {
        my $taxon = $tip->get_taxon;
        META: for my $meta ( @{ $taxon->get_meta('skos:closeMatch', 'skos:exactMatch') } ) {
            my $obj = $meta->get_object;
            if ( $obj =~ m|http://purl.uniprot.org/taxonomy/(\d+)| ) {
                my $id = $1;
                $tip->set_name($id);
                $taxon->set_name($id);
                last META;
            }
        }
    }
}

# create mrp matrix
my $matrix = $forest->make_matrix;

# create a simple hash keyed on ncbi taxon ids, with values the character
# state sequences. only keep those key value pairs that are seen in taxa.csv
my %simple;
my $nchar;
for my $row ( @{ $matrix->get_entities } ) {
    my $name = $row->get_name;
    if ( $seen{$name} ) {
        my @char = $row->get_char;
        $simple{$name} = \@char;
        $nchar = scalar @char;
    }
}

# only keep phylogenetically informative columns. these mrp matrices *can*
# have uninformative columns because we've pruned rows. also, they now may
# have duplicate 'site patterns', which we also prune
my %informative = map { $_ => [] } keys %simple;
my @names = keys %simple;
my %pattern;
for my $i ( 0 .. ( $nchar - 1 ) ) {
    my ( %char, @char, $pattern );    
    for my $name ( @names ) {
        $char{$simple{$name}->[$i]}++;
        push @char, $simple{$name}->[$i];
        $pattern .= $simple{$name}->[$i];
    }
    if ( scalar(keys(%char)) > 1 && ! $pattern{$pattern} ) {
        for my $j ( 0 .. $#names ) {
            push @{ $informative{$names[$j]} }, $char[$j];
        }
    }
    $pattern{$pattern}++;
}

# print as simple key/value table
for my $row ( keys %informative ) {
    print $row, "\t", join('', @{ $informative{$row} } ), "\n";
}