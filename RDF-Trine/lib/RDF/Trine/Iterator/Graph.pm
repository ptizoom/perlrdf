# RDF::Trine::Iterator::Graph
# -----------------------------------------------------------------------------

=head1 NAME

RDF::Trine::Iterator::Graph - Stream (iterator) class for graph query results.

=head1 SYNOPSIS

    use RDF::Trine::Iterator;
    
    my $iterator = RDF::Trine::Iterator::Graph->new( \&data );
    while (my $statement = $iterator->next) {
    	# do something with $statement
    }

=head1 METHODS

=over 4

=cut

package RDF::Trine::Iterator::Graph;

use strict;
use warnings;
no warnings 'redefine';

use JSON;
use List::Util qw(max);
use Scalar::Util qw(blessed);

use RDF::Trine::Iterator qw(sgrep);
use RDF::Trine::Iterator::Graph::Materialized;

use base qw(RDF::Trine::Iterator);

######################################################################

our ($VERSION);
BEGIN {
	$VERSION	= 0.109;
}

######################################################################


=item C<new ( \@results, %args )>

=item C<new ( \&results, %args )>

Returns a new SPARQL Result interator object. Results must be either
an reference to an array containing results or a CODE reference that
acts as an iterator, returning successive items when called, and
returning undef when the iterator is exhausted.

$type should be one of: bindings, boolean, graph.

=cut

sub new {
	my $class		= shift;
	my $stream		= shift || sub { undef };
# 	Carp::confess unless (scalar(@_) % 2 == 0);
	my %args		= @_;
	
	my $type		= 'graph';
	return $class->SUPER::new( $stream, $type, [], %args );
}

sub _new {
	my $class	= shift;
	my $stream	= shift;
	my $type	= shift;
	my $names	= shift;
	my %args	= @_;
	return $class->new( $stream, %args );
}

=item C<< as_bindings ( $s, $p, $o ) >>

Returns the iterator as a Bindings iterator, using the supplied triple nodes to
determine the variable bindings.

=cut

sub as_bindings {
	my $self	= shift;
	my @nodes	= @_;
	my @names	= qw(subject predicate object context);
	my %bindings;
	foreach my $i (0 .. $#names) {
		if (not($nodes[ $i ]) or not($nodes[ $i ]->isa('RDF::Trine::Node::Variable'))) {
			$nodes[ $i ]	= RDF::Trine::Node::Variable->new( $names[ $i ] );
		}
	}
	foreach my $i (0 .. $#nodes) {
		my $n	= $nodes[ $i ];
		$bindings{ $n->name }	= $names[ $i ];
	}
	my $context	= $nodes[ 3 ]->name;
	
	my $sub	= sub {
		my $statement	= $self->next;
		return undef unless ($statement);
		my %values		= map {
			my $method = $bindings{ $_ };
			$_ => $statement->$method()
		} grep { ($statement->isa('RDF::Trine::Statement::Quad')) ? 1 : ($_ ne $context) } (keys %bindings);
		return \%values;
	};
	return RDF::Trine::Iterator::Bindings->new( $sub, [ keys %bindings ] );
}

=item C<< materialize >>

Returns a materialized version of the current graph iterator.

=cut

sub materialize {
	my $self	= shift;
	my @data	= $self->get_all;
	my @args	= $self->construct_args;
	return $self->_mclass->_new( \@data, @args );
}

sub _mclass {
	return 'RDF::Trine::Iterator::Graph::Materialized';
}


=item C<< unique >>

Returns a Graph iterator that ensures the returned statements are unique. While
the underlying RDF graph is the same regardless of uniqueness, the iterator's
serialization methods assume the results are unique, and so use this method
before serialization.

Uniqueness is opt-in for efficiency concerns -- this method requires O(n) memory,
and so may have noticable effects on large graphs.

=cut

sub unique {
	my $self	= shift;
	my %seen;
	no warnings 'uninitialized';
	my $stream	= sgrep( sub {
		my $s	= $_;
		my $str	= $s->as_string;
		not($seen{ $str }++)
	}, $self);
	return $stream;
}

=item C<is_graph>

Returns true if the underlying result is an RDF graph.

=cut

sub is_graph {
	my $self			= shift;
	return 1;
}

=item C<as_xml ( $max_size )>

Returns an XML serialization of the stream data.

=cut

sub as_xml {
	my $self	= shift;
	my $max_result_size	= shift || 0;
	my $string	= '';
	open( my $fh, '>', \$string );
	$self->print_xml( $fh, $max_result_size );
	return $string;
}

=item C<< print_xml ( $fh, $max_size ) >>

Prints an XML serialization of the stream data to the filehandle $fh.

=cut

sub print_xml {
	my $self			= shift;
	my $fh				= shift;
	my $max_result_size	= shift || 0;
	my $graph			= $self->unique();
	
	my $count	= 0;
	no strict 'refs';
	print {$fh} <<"END";
<?xml version="1.0" encoding="utf-8"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
END
	while (my $stmt = $graph->next) {
		if ($max_result_size) {
			last if ($count++ >= $max_result_size);
		}
		my $p		= $stmt->predicate->uri_value;
		my $pos		= max( rindex( $p, '/' ), rindex( $p, '#' ) );
		my $ns		= substr($p,0,$pos+1);
		my $local	= substr($p, $pos+1);
		my $subject	= $stmt->subject;
		my $subjstr	= ($subject->is_resource)
					? 'rdf:about="' . $subject->uri_value . '"'
					: 'rdf:nodeID="' . $subject->blank_identifier . '"';
		my $object	= $stmt->object;
		
		print {$fh} qq[<rdf:Description $subjstr>\n];
		if ($object->is_resource) {
			my $uri	= $object->uri_value;
			print {$fh} qq[\t<${local} xmlns="${ns}" rdf:resource="$uri"/>\n];
		} elsif ($object->is_blank) {
			my $id	= $object->blank_identifier;
			print {$fh} qq[\t<${local} xmlns="${ns}" rdf:nodeID="$id"/>\n];
		} else {
			my $value	= $object->literal_value;
			# escape < and & and ' and " and >
			$value	=~ s/&/&amp;/g;
			$value	=~ s/'/&apos;/g;
			$value	=~ s/"/&quot;/g;
			$value	=~ s/</&lt;/g;
			$value	=~ s/>/&gt;/g;
			
			my $tag		= qq[${local} xmlns="${ns}"];
			if (defined($object->literal_value_language)) {
				my $lang	= $object->literal_value_language;
				$tag	.= qq[ xml:lang="${lang}"];
			} elsif (defined($object->literal_datatype)) {
				my $dt	= $object->literal_datatype;
				$tag	.= qq[ rdf:datatype="${dt}"];
			}
			print {$fh} qq[\t<${tag}>${value}</${local}>\n];
		}
		print {$fh} qq[</rdf:Description>\n];
	}
	print {$fh} "</rdf:RDF>\n";
}

=item C<as_json ( $max_size )>

Returns a JSON serialization of the stream data.

=cut

sub as_json {
	my $self			= shift;
	my $max_result_size	= shift;
	throw RDF::Trine::Error::SerializationError ( -text => 'There is no JSON serialization specified for graph query results' );
}

=item C<< construct_args >>

Returns the arguments necessary to pass to the stream constructor _new
to re-create this stream (assuming the same closure as the first

=cut

sub construct_args {
	my $self	= shift;
	my $type	= $self->type;
	my $args	= $self->_args || {};
	return ($type, [], %{ $args });
}


1;

__END__

=back

=head1 DEPENDENCIES

L<JSON|JSON>

L<Scalar::Util|Scalar::Util>


=head1 AUTHOR

Gregory Todd Williams  C<< <gwilliams@cpan.org> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2007, Gregory Todd Williams C<< <gwilliams@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


