use strict;
use warnings;

use JSON::XS;
use Encode;

my $json    = JSON::XS->new->utf8;
my $CRLF = "\x0D\x0A";

my %users = ();
my %ques  = ();

{
    package QPollFH;
    use Coro::Channel;
    
    sub new {
        my $class = shift;

        my $q = Coro::Channel->new;

        $ques{$q} = $q;

        while ( my ($email, $line) = each %users ) {
            $q->put($json->encode([$email, $line]) . $CRLF);
        }

        bless \$q => $class;
    }
    sub getline {
        ${$_[0]}->get;
    }
    sub close {
        # うごいてない
        delete $ques{$$_[0]};
    }
}

my $app = sub {
    my $env = shift;

    if ( $env->{'PATH_INFO'} eq '/pull' ) {
        return [200, ['Content-Type' => 'text/plain'], QPollFH->new];
    }
    elsif ( $env->{'PATH_INFO'} eq '/post' ) {
        my $input = $env->{'psgi.input'};
        my $email = <$input>;
        $email =~ tr/\x0D\x0A//d;
        $users{$email} = '';
        putall($json->encode([$email, '']) . $CRLF);

        while ( my $line = <$input> ) {
            $line =~ s/\x0D?\x0A?$//;
            $line =~ s/\\r//g;
            $line = $json->decode($line)->[0];
            $users{$email} = $line;
            putall($json->encode([$email, $line]) . $CRLF);
        }
    }


    return ['200', [], ['hello']]; 
};


sub putall {
    my $line = shift;
    $_->put($line) for values %ques;
}




use Plack::Middleware::Static;
$app = Plack::Middleware::Static->wrap($app, path => qr/^\/static/, root => '.', followsymlinks => 1);

