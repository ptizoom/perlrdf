# RDF::Query::CostModel::Naive
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Query::CostModel::Naive - Execution cost estimator

=head1 METHODS

=over 4

=cut

package RDF::Query::CostModel::Naive;

our ($VERSION);
BEGIN {
	$VERSION	= '2.002';
}

use strict;
use warnings;
no warnings 'redefine';
use base qw(RDF::Query::CostModel);

use RDF::Query::Error qw(:try);

use Set::Scalar;
use Data::Dumper;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(uniq);

=item C<< new () >>

Return a new cost model object.

=cut

sub new {
	my $class	= shift;
	my $self	= $class->SUPER::new( @_ );
	return $self;
}


sub _cost_service {
	my $self	= shift;
	my $plan	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $plan->sse( {}, '' ) );
	my $card	= $self->_cardinality( $plan, $context );
	my $cost	= $self->cost( $plan->pattern, $context );
	$l->debug( sprintf('COST of Service is %d + %d', $card, $cost) );
	return $card + $cost;
}

sub _cost_union {
	my $self	= shift;
	my $plan	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $plan->sse( {}, '' ) );
	return $self->cost( $plan->lhs, $context ) + $self->cost( $plan->rhs, $context );
}

sub _cost_filter {
	my $self	= shift;
	my $plan	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $plan->sse( {}, '' ) );
	return $self->_cardinality( $plan, $context ) + $self->cost( $plan->pattern, $context );
}

sub _cost_project {
	my $self	= shift;
	my $plan	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $plan->sse( {}, '' ) );
	return $self->_cardinality( $plan, $context ) + $self->cost( $plan->pattern, $context );
}

sub _cost_constant {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $pattern->sse( {}, '' ) );
	return $self->_cardinality( $pattern, $context );
}

sub _cost_nestedloop {
	my $self	= shift;
	my $bgp		= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $bgp->sse( {}, '' ) );
	my $lhscost	= $self->cost( $bgp->lhs, $context );
	my $rhscost	= $self->cost( $bgp->rhs, $context );
	my $card	= $self->_cardinality( $bgp, $context );
	$l->debug( sprintf('COST of NestedLoop is %d + (%d + %d)', $card, $lhscost, $rhscost) );
	return $card + $lhscost + $rhscost;
}

sub _cost_pushdownnestedloop {
	my $self	= shift;
	my $bgp		= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $bgp->sse( {}, '' ) );
	my $lhscost	= $self->cost( $bgp->lhs, $context );
	
	$context->pushstack();
	my $bound	= { %{ $context->bound } };
	$context->bound( $bound );
	
	my $lhs		= $bgp->lhs;
	my @vars	= $lhs->referenced_variables;
	foreach my $name (@vars) {
		$bound->{ $name }	= RDF::Query::Node::Blank->new();	# temporary bound variable to that the costs compute correctly
	}
	
	my $lhscard 		= $self->_cardinality( $bgp->lhs, $context );
	my $single_rhscost	= $self->cost( $bgp->rhs, $context );
	$l->debug( sprintf('COST of PushDownNestedLoop is %d + (%d * %d)', $lhscost, $lhscard, $single_rhscost) );
	my $rhscost			= $lhscard * $single_rhscost;
	$context->popstack();
	
	return  $lhscost + $rhscost;
}

sub _cost_triple {
	my $self	= shift;
	my $triple	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $triple->sse( {}, '' ) );
	return $self->_cardinality( $triple, $context );
}

sub _cost_quad {
	my $self	= shift;
	my $quad	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $quad->sse( {}, '' ) );
	return $self->_cardinality( $quad, $context );
}

sub _cost_distinct {
	my $self	= shift;
	my $plan	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	$l->debug( 'Computing COST: ' . $plan->sse( {}, '' ) );
	return $self->_cardinality( $plan, $context ) + $self->cost( $plan->pattern, $context );
}

################################################################################

sub _cardinality_triple {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	my $size	= $self->_size;
	my $bf		= $pattern->bf( $context );
	my $f		= ($bf =~ tr/f//);
	my $r		= $f / 3;
	$l->debug( "Pattern has bf representation '$bf'" );
	$l->debug( "There are $f of 3 free variables" );
	my $card	= ($self->_size ** $r);
	$l->debug( 'Cardinality of triple is : ' . $card );
	
	# round the cardinality to an integer
	return int($card + .5 * ($card <=> 0));
}

sub _cardinality_quad {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	my $size	= $self->_size;
	my $bf		= $pattern->bf( $context );
	my $f		= ($bf =~ tr/f//);
	my $r		= $f / 4;
	$l->debug( "Pattern has bf representation '$bf'" );
	$l->debug( "There are $f of 4 free variables" );
	my $card	= ($self->_size ** $r);
	$l->debug( 'Cardinality of quad is : ' . $card );
	
	# round the cardinality to an integer
	return int($card + .5 * ($card <=> 0));
}

sub _cardinality_filter {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	return $self->_cardinality( $pattern->pattern, $context );
}

sub _cardinality_distinct {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	return $self->_cardinality( $pattern->pattern, $context );
}

sub _cardinality_project {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	return $self->_cardinality( $pattern->pattern, $context );
}

sub _cardinality_service {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	return $self->_cardinality( $pattern->pattern, $context );	# XXX this isn't really right. it uses the local data to estimate the cardinality of the remote query...
}

sub _cardinality_union {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	return $self->_cardinality( $pattern->lhs, $context ) + $self->_cardinality( $pattern->rhs, $context );
}

sub _cardinality_nestedloop {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my $size	= $self->_size;

	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	my $cardinality;
	try {
		my @bf		= $pattern->bf( $context );
		my @triples	= ($pattern->rhs, $pattern->lhs);
		
		my %seen_frees;
		my $card	= 1;
		foreach my $i (0 .. $#bf) {
			my $const	= RDF::Query::Node::Literal->new('');
			my $bf		= $bf[ $i ];
			my $t		= $triples[ $i ];
			my @f		= ($bf =~ m/(\d+)/g);
			my $f		= scalar(@f);
			my $actually_free	= 0;
			foreach my $f (@f) {
				$actually_free++ unless ($seen_frees{ $f });
			}
			@seen_frees{ @f }	= (1) x $f;
			
			if ($f != $actually_free) {
				my $diff	= $f - $actually_free;
				$l->debug("- NestedLoop triple {" . $t->sse( {}, '' ) . "} has $diff variables that will be bound by previous triples.");
			}
			
			my $r		= $actually_free / 3;
			my $tcard	= ($self->_size ** $r);
			$card		*= $tcard;
		}
		$l->debug( 'Cardinality of NestedLoop join is : ' . $card );
		
		# round the cardinality to an integer
		$cardinality	= int($card + .5 * ($card <=> 0));
	} catch RDF::Query::Error::ExecutionError with {
		my $lhs	= $self->_cardinality( $pattern->lhs, $context );
		unless (defined($lhs)) {
			warn "Computing cardinality of LHS of NestedLoop join failed";
			throw RDF::Query::Error::ExecutionError -text => "Computing cardinality of LHS of NestedLoop join failed";
		}
		
		my $rhs	= $self->_cardinality( $pattern->rhs, $context );
		unless (defined($rhs)) {
			warn "Computing cardinality of RHS of NestedLoop join failed";
			throw RDF::Query::Error::ExecutionError -text => "Computing cardinality of RHS of NestedLoop join failed";
		}
		
		$cardinality	= $lhs * $rhs;
	};
	return $cardinality;
}

sub _cardinality_pushdownnestedloop {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my @triples	= ($pattern->rhs, $pattern->lhs);
	my $size	= $self->_size;
	
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	my $cardinality;
	try {
		my @bf		= $pattern->bf( $context );
		
		my %seen_frees;
		my $card	= 1;
		foreach my $i (0 .. $#bf) {
			my $const	= RDF::Query::Node::Literal->new('');
			my $bf		= $bf[ $i ];
			my $t		= $triples[ $i ];
			my @f		= ($bf =~ m/(\d+)/g);
			my $f		= scalar(@f);
			my $actually_free	= 0;
			foreach my $f (@f) {
				$actually_free++ unless ($seen_frees{ $f });
			}
			@seen_frees{ @f }	= (1) x $f;
			
			if ($f != $actually_free) {
				my $diff	= $f - $actually_free;
				$l->debug("- PushDownNestedLoop triple {" . $t->sse( {}, '' ) . "} has $diff variables that will be bound by previous triples.");
			}
			
			my $r		= $actually_free / 3;
			my $tcard	= ($self->_size ** $r);
			$card		*= $tcard;
		}
		$l->debug( 'Cardinality of PushDownNestedLoop is : ' . $card );
		
		# round the cardinality to an integer
		$cardinality	= int($card + .5 * ($card <=> 0));
	} catch RDF::Query::Error::ExecutionError with {
		my $lhs	= $self->_cardinality( $pattern->lhs, $context );
		unless (defined($lhs)) {
			throw RDF::Query::Error::ExecutionError -text => "Computing cardinality of LHS of PushDownNestedLoop join failed";
		}
		
		my $rhs	= $self->_cardinality( $pattern->rhs, $context );
		unless (defined($rhs)) {
			throw RDF::Query::Error::ExecutionError -text => "Computing cardinality of RHS of PushDownNestedLoop join failed";
		}
		
		$cardinality	= $lhs * $rhs;
	};
	return $cardinality;
}

sub _cardinality_constant {
	my $self	= shift;
	my $pattern	= shift;
	my $context	= shift;
	my $l		= Log::Log4perl->get_logger("rdf.query.costmodel");
	my $card	= $pattern->size;
	$l->trace('Cardinality of Constant is ' . $card);
	return $card;
}

1;

__END__

=back

=head1 AUTHOR

 Gregory Todd Williams <gwilliams@cpan.org>

=cut