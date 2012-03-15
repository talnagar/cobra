#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;
use Bio::Phylo::Cobra::TaxaMap;
use Bio::Phylo::IO qw'parse unparse';
use Bio::Phylo::Util::CONSTANT qw':objecttypes :namespaces';
use Bio::Phylo::Factory;

# process command line arguments
my ( $infile, $csv, $og );
GetOptions(
    'infile=s'   => \$infile,
    'csv=s'      => \$csv,
    'outgroup=s' => \$og,
);

# build nexus string from $infile only keeping distinct trees
my %seen;
my $nexus_string;
{
    open my $fh, '<', $infile or die $!;
    while(<$fh>) {
        if ( /tree PAUP_\d+ = \[&U\] (\(.+\);)/ ) {
            my $newick = $1;
            $nexus_string .= $_ if not $seen{$newick}++;
        }
        else {
            $nexus_string .= $_;
        }
    }
}

# parse nexus string with distinct trees
my $project = parse(
    '-format' => 'nexus',
    '-string' => $nexus_string,
    '-as_project' => 1
);

# build consensus tree
my ($forest) = @{ $project->get_items(_FOREST_) };
my $tree = $forest->make_consensus;

# delete original forest with distinct trees
$project->delete($forest);

# create new forest, add consensus tree, make taxa
my $fac = Bio::Phylo::Factory->new;
$forest = $fac->create_forest;
$forest->insert($tree);
my $taxa = $forest->make_taxa;
$forest->set_taxa($taxa);
$project->insert($taxa,$forest);

# re-root on MRP outgroup
my $outgroup = $tree->get_by_name($og);
$outgroup->set_root_below;
$tree->prune_tips([$outgroup]);
$tree->remove_unbranched_internals;

# warn for polytomies
$tree->visit(
    sub {
        my $node = shift;
        if ( scalar(@{ $node->get_children }) > 2 ) {
            warn $node->to_newick;
        }
    }
);

# resolve polytomies
$tree->resolve;

# attach 10-character code (from csv) and binomial
# as phyloxml annotations
my $map = Bio::Phylo::Cobra::TaxaMap->new($csv);
$taxa->visit(
    sub {
        my $taxon = shift;
        my $code = $taxon->get_name;
        my ($binomial) = sort { length($a) <=> length($b) } $map->get_binomial_for_code($code);
        if ( $code ) {
            $taxon->add_meta(
                $fac->create_meta(
                    '-namespaces' => { 'pxml' => _NS_PHYLOXML_ },
                    '-triple' => { 'pxml:code' => $code },
                )
            );
        }
        #$taxon->add_meta(
        #    $fac->create_meta(
        #        '-namespaces' => { 'pxml' => _NS_PHYLOXML_ },
        #        '-triple' => { 'pxml:scientific_name' => $binomial },
        #    )
        #);            
    }
);

# print output
print unparse( '-format' => 'phyloxml', '-phylo' => $project );