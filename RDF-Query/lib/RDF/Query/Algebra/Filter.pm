# RDF::Query::Algebra::Filter
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::Algebra::Filter - Algebra class for Filter expressions

=cut

package RDF::Query::Algebra::Filter;

use strict;
use warnings;
no warnings 'redefine';
use base qw(RDF::Query::Algebra);

use Data::Dumper;
use List::MoreUtils qw(uniq);
use Carp qw(carp croak confess);
use Scalar::Util qw(blessed reftype);

use RDF::Query::Error qw(:try);
use RDF::Trine::Iterator qw(sgrep smap swatch);

######################################################################

our ($VERSION);
BEGIN {
	$VERSION	= '2.002';
}

######################################################################

# function
# operator
# 	unary
# 	binary


=head1 METHODS

=over 4

=cut

=item C<new ( $expression, $pattern )>

Returns a new Filter structure.

=cut

sub new {
	my $class	= shift;
	my $expr	= shift;
	my $pattern	= shift;
	Carp::confess "Not an algebra pattern: " . Dumper($pattern) unless ($pattern->isa('RDF::Query::Algebra'));
	unless ($pattern->isa('RDF::Query::Algebra::GroupGraphPattern') or $pattern->isa('RDF::Query::Algebra::Filter')) {
		# for proper serialization, the pattern needs to be a GGP or another filter
		$pattern	= RDF::Query::Algebra::GroupGraphPattern->new( $pattern );
	}
	return bless( [ 'FILTER', $expr, $pattern ] );
}

=item C<< construct_args >>

Returns a list of arguments that, passed to this class' constructor,
will produce a clone of this algebra pattern.

=cut

sub construct_args {
	my $self	= shift;
	return ($self->expr, $self->pattern);
}

=item C<< expr >>

Returns the filter expression.

=cut

sub expr {
	my $self	= shift;
	if (@_) {
		$self->[1]	= shift;
	}
	return $self->[1];
}

=item C<< pattern >>

Returns the filter pattern.

=cut

sub pattern {
	my $self	= shift;
	if (@_) {
		$self->[2]	= shift;
	}
	return $self->[2];
}

=item C<< sse >>

Returns the SSE string for this alegbra expression.

=cut

sub sse {
	my $self	= shift;
	my $context	= shift;
	
	return sprintf(
		'(filter %s %s)',
		$self->expr->sse( $context ),
		$self->pattern->sse( $context ),
	);
}

=item C<< as_sparql >>

Returns the SPARQL string for this alegbra expression.

=cut

sub as_sparql {
	my $self	= shift;
	my $context	= shift;
	my $indent	= shift || '';
	
	my $expr	= $self->expr;
	my $filter_sparql	= $expr->as_sparql( $context, $indent );
	my $pattern_sparql	= $self->pattern->as_sparql( $context, $indent );
	$pattern_sparql		=~ s#}\s*$#${indent}\tFILTER ${filter_sparql} .\n${indent}}#;
	return $pattern_sparql;
}

=item C<< type >>

Returns the type of this algebra expression.

=cut

sub type {
	return 'FILTER';
}

=item C<< referenced_variables >>

Returns a list of the variable names used in this algebra expression.

=cut

sub referenced_variables {
	my $self	= shift;
	my $expr	= $self->expr;
	my $pattern	= $self->pattern;
	my @vars	= $pattern->referenced_variables;
	if (blessed($expr) and $expr->isa('RDF::Query::Algebra')) {
		return uniq(@vars, $self->expr->referenced_variables);
	} elsif (blessed($expr) and $expr->isa('RDF::Query::Node::Variable')) {
		return uniq(@vars, $expr->name);
	} else {
		return (@vars);
	}
}

=item C<< definite_variables >>

Returns a list of the variable names that will be bound after evaluating this algebra expression.

=cut

sub definite_variables {
	my $self	= shift;
	my $pattern	= $self->pattern;
	return $pattern->definite_variables;
}

=item C<< fixup ( $query, $bridge, $base, \%namespaces ) >>

Returns a new pattern that is ready for execution using the given bridge.
This method replaces generic node objects with bridge-native objects.

=cut

sub fixup {
	my $self	= shift;
	my $class	= ref($self);
	my $query	= shift;
	my $bridge	= shift;
	my $base	= shift;
	my $ns		= shift;
	
	if (my $opt = $query->algebra_fixup( $self, $bridge, $base, $ns )) {
		return $opt;
	} else {
		my $expr	= $self->expr;
		if ($expr->isa('RDF::Query::Algebra')) {
			$expr	= $expr->fixup( $query, $bridge, $base, $ns );
		}
		my $pattern	= $self->pattern->fixup( $query, $bridge, $base, $ns );
		return $class->new( $expr, $pattern );
	}
}

=item C<< is_solution_modifier >>

Returns true if this node is a solution modifier.

=cut

sub is_solution_modifier {
	return 0;
}


1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut
