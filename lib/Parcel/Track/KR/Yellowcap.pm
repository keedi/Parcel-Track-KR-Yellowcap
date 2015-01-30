package Parcel::Track::KR::Yellowcap;
# ABSTRACT: Parcel::Track driver for the Yellowcap (옐로우캡)

use utf8;

use Moo;

our $VERSION = '0.002';

with 'Parcel::Track::Role::Base';

use HTML::Selector::XPath;
use HTML::TreeBuilder::XPath;
use HTTP::Tiny;

#
# to support HTTPS
#
use IO::Socket::SSL;
use Mozilla::CA;
use Net::SSLeay;

our $URI =
    'https://www.kgyellowcap.co.kr/delivery/waybill.html?mode=bill&delivery=%s';
our $AGENT = 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';

sub BUILDARGS {
    my ( $class, @args ) = @_;

    my %params;
    if ( ref $args[0] eq 'HASH' ) {
        %params = %{ $args[0] };
    }
    else {
        %params = @args;
    }
    $params{id} =~ s/\D//g;

    return \%params;
}

sub uri { sprintf( $URI, $_[0]->id ) }

sub track {
    my $self = shift;

    my %result = (
        from   => q{},
        to     => q{},
        result => q{},
        htmls  => [],
        descs  => [],
    );

    my $http = HTTP::Tiny->new(
        agent      => $AGENT,
        verify_SSL => 1,
    );

    my $res = $http->post_form( $self->uri, { delivery => $self->id } );
    unless ( $res->{success} ) {
        $result{result} = 'failed to get parcel tracking info from the site';
        return \%result;
    }

    #
    # http://stackoverflow.com/questions/19703341/disabling-html-entities-expanding-in-htmltreebuilder-perl-module
    #
    my $tree = HTML::TreeBuilder::XPath->new;
    $tree->ignore_unknown(0);
    $tree->no_expand_entities(1);
    $tree->attr_encoded(1);
    $tree->parse( $res->{content} );
    $tree->eof;

    my $prefix = '/html/body/div[2]/div[2]/div[1]';

    my $html1 = ( $tree->findnodes("$prefix/table[1]") )[0];
    my $html2 = ( $tree->findnodes("$prefix/table[2]") )[0];
    unless ( $html1 && $html2 ) {
        $result{result} = 'cannot find such parcel info';
        return \%result;
    }

    my $found      = ( $tree->findnodes("$prefix/table[2]/tbody/tr/td") )[0];
    my $found_text = $found ? $found->as_text : q{};
    my $not_found  = Encode::encode_utf8('조회된 데이터가 없습니다');
    if ( $found_text =~ m/$not_found/ ) {
        $result{result} = 'cannot find such parcel info';
        return \%result;
    }

    $result{from}  = $tree->findvalue("$prefix/table[1]/tbody/tr[1]/td[2]");
    $result{to}    = $tree->findvalue("$prefix/table[1]/tbody/tr[2]/td[2]");
    $result{htmls} = [ $html1->as_HTML, $html2->as_HTML ];

    my @elements = $tree->findnodes("$prefix/table[2]/tbody/tr");
    for my $e (@elements) {
        my @texts = map {
            my $text = $_->as_text;
            $text =~ s/&nbsp;/ /gms;
            $text =~ s/(^\s+|\s+$)//gms;
            $text =~ s/ +/ /gms;
            $text;
        } $e->look_down( '_tag', 'td' );

        push @{ $result{descs} }, join( q{ }, @texts[ 0, 2, 1, 3 ] );

        $result{result} = join( q{ }, @texts[ 0, 1 ] );
    }

    return \%result;
}

1;

# COPYRIGHT

__END__

=for Pod::Coverage BUILDARGS

=head1 SYNOPSIS

    use Parcel::Track;

    # Create a tracker
    my $tracker = Parcel::Track->new( 'KR::Yellowcap', '1234-5678-901' );

    # ID & URI
    print $tracker->id . "\n";
    print $tracker->uri . "\n";
    
    # Track the information
    my $result = $tracker->track;
    
    # Get the information what you want.
    if ( $result ) {
        print "$result->{from}\n";
        print "$result->{to}\n";
        print "$result->{result}\n";
        print "$_\n" for @{ $result->{descs} };
        print "$_\n" for @{ $result->{htmls} };
    }
    else {
        print "Failed to track information\n";
    }


=attr id

=method track

=method uri


=head1 SEE ALSO

=for :list
* L<Parcel::Track>
* L<KG Yellowcap (KG 옐로우캡)|https://www.kgyellowcap.co.kr/>
