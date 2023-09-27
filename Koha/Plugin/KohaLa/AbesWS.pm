package Koha::Plugin::KohaLa::AbesWS;

use Modern::Perl;
use utf8;
use base qw(Koha::Plugins::Base);
use CGI qw(-utf8);
use C4::Context;
use C4::Biblio;
use Koha::Cache;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Template;
use Encode qw/ decode /;
use YAML;


## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'KohaLa AbesWS',
    canonicalname   => 'koha-plugin-kohala-abesws',
    description     => 'Utilisation de services web Abes',
    author          => 'Tamil s.a.r.l.',
    date_authored   => '2021-03-31',
    date_updated    => "2023-09-27",
    minimum_version => '22.11.00.000',
    maximum_version => undef,
    copyright       => '2023',
    version         => '1.0.9',
};


my $conf = {
    bibliocontrol => {
        errors => [
            'une 225 est presente sans 410 ni 461',
            'une 700 701 702 n a pas de code fonction',
            'une 181 est presente en meme temps qu une 200$b',
        ],
    },
    algo => {
        tdoc => {
            bib => {
                Aa => 'Monographie imprimée',
                Ab => 'Périodique imprimé',
                Ad => 'Collection imprimée',
                Ba => 'Document audiovisuel',
                Ga => 'Enregistrement sonore musical',
                Ka => 'Carte imprimée',
                Ma => 'Partition imprimée',
                Na => 'Enregistrement sonore non musical',
                Oa => 'Document électronique',
                Ob => 'Périodique électronique',
                Od => 'Collection de documents électroniques',
                Or => 'Recueil factice de documents électroniques',
                Va => 'Objet',
                Za => 'Document multimédia multisupport',
                Zd => 'Collection de documents multimédias multisupports',
            },
            aut => {
                Tb => 'Collectivité / Congrès',
                Td => 'Noms communs',
                Tp => 'Nom de personne',
                Tu => 'Titre uniforme',
            },
        },
    },
};

$conf->{algo}->{tdoc}->{get_array} = sub {
    my @tdocs;
    for ( (['bib', 'Biblio'], ['aut', 'Autorité']) ) {
        my ($code, $type) = @$_;
        my $tdoc = $conf->{algo}->{tdoc}->{$code};
        for ( keys %$tdoc ) {
            push @tdocs, [$_, "$type: " . $tdoc->{$_}];
        }
    }
    return \@tdocs;
};

$conf->{algo}->{tdoc}->{get_hash} = sub {
    my %tdoc_hash;
    for ( (['bib', 'Biblio'], ['aut', 'Autorité']) ) {
        my ($code, $type) = @$_;
        my $tdoc = $conf->{algo}->{tdoc}->{$code};
        for ( keys %$tdoc ) {
            $tdoc_hash{$_} = "$type: " . $tdoc->{$_};
        }
    }
    return \%tdoc_hash;
};

sub new {
    my ($class, $args) = @_;

    $args->{metadata} = $metadata;
    $args->{metadata}->{class} = $class;
    $args->{cache} = Koha::Cache->new();

    $class->SUPER::new($args);
}

sub config {
    my $self = shift;

    my $c = $self->{args}->{c};
    unless ($c) {
        $c = $self->retrieve_data('c');
        if ($c) {
            utf8::encode($c);
            $c = decode_json($c);
        }
        else {
            $c = {};
        }
    }
    $c->{url} ||= {};
    $c->{url}->{api} ||= 'https://www.sudoc.fr/services';
    $c->{url}->{algo} ||= 'https://www.idref.fr/AlgoLiens';
    $c->{url}->{timeout} ||= 600;
    $c->{opac}->{publication}->{expiry} = 86400;
    $c->{metadata} = $self->{metadata};

    my @rcr = split /\r|\n/, $c->{iln}->{rcr};
    @rcr = grep { $_ } @rcr;
    @rcr = map {
        /^([0-9]+) +(.+)$/ ? [$1, $2] : [$_, $_];
    } @rcr;
    $c->{iln}->{rcr_array} = \@rcr;

    my %bib_per_rcr = map { $_->[0] => $_->[1] } @rcr;
    $c->{iln}->{rcr_hash} = \%bib_per_rcr;

    $self->{args}->{c} = $c;

    return $c;
}

sub get_form_config {
    my $cgi = shift;
    my $c = {
        url => {
            api     => undef,
            algo    => undef,
            timeout => undef,
        },
        iln => {
            iln => undef,
            rcr => undef,
            ppn => undef,
        },
        bibliocontrol => {
            t225 => 0,
            f000 => 0,
            t181 => 0,
            link_koha => 'marc',
        },
        detail => {
            enabled => 0,
            location => 0,
            ppn_selector => undef,
        },
        opac => {
            publication => {
                enabled => 0,
            },
        },
    };

    my $set;
    $set = sub {
        my ($node, $path) = @_;
        return if ref($node) ne 'HASH';
        for my $subkey ( keys %$node ) {
            my $key = $path ? "$path.$subkey" : $subkey;
            my $subnode = $node->{$subkey};
            if ( ref($subnode) eq 'HASH' ) {
                $set->($subnode, $key);
            }
            else {
                $node->{$subkey} = $cgi->param($key);
            }
        }
    };

    $set->($c);
    return $c;
}

sub configure {
    my ($self, $args) = @_;
    my $cgi = $self->{'cgi'};

    if ( $cgi->param('save') ) {
        my $c = get_form_config($cgi);
        my $rcr = [
            map { s/'/''/g }
            split /\n/, $c->{iln}->{rcr}
        ];
        $self->store_data({ c => encode_json($c) });
        print $self->{'cgi'}->redirect(
            "/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::KohaLa::AbesWS&method=tool");
    }
    else {
        my $template = $self->get_template({ file => 'configure.tt' });
        $template->param( c => $self->config() );
        $self->output_html( $template->output() );
    }
}

sub tool {
    my ($self, $args) = @_;

    my $cgi = $self->{cgi};

    my $template;
    my $c = $self->config();
    my $ws = $cgi->param('ws');
    if ( $ws ) {
        if ($ws eq 'bibliocontrol') {   
            $template = $self->get_template({ file => 'bibliocontrol.tt' });
            my $rcr = $cgi->param('rcr');
            if ($rcr) {
                $template->param( rcr => $rcr );
                $template->param( bibs => $self->get_bibliocontrol($rcr) );
            }
            else {      
                $template->param( rcr_select => $c->{iln}->{rcr_array} );
            }
        }
        elsif ($ws eq 'algo') {
            $template = $self->get_template({ file => 'algo.tt' });
            my @rcr = $cgi->multi_param('rcr');
            my @tdoc = $cgi->multi_param('tdoc');
            if (@rcr) {
                $template->param( rcr_hash => $c->{iln}->{rcr_hash} );
                $template->param( tdoc_hash => $conf->{algo}->{tdoc}->{get_hash}->() );
                $template->param( recs => $self->get_algo(\@rcr, \@tdoc) );
            }
            else {
                $template->param( rcr_select => $c->{iln}->{rcr_array} );
                $template->param( tdoc_select => $conf->{algo}->{tdoc}->{get_array}->() );
            }
        }
    }
    else {
        $template = $self->get_template({ file => 'home.tt' });
    }
    $template->param( c => $self->config() );
    $template->param( WS => $ws ) if $ws;
    $self->output_html( $template->output() );
}

sub get_biblio_per_ppn {
    my ($self, $ppn) = @_;

    my $sth = $self->{args}->{sth_biblio};
    unless ($sth) {
        my $c = $self->config();
        my $ppn_field = $c->{iln}->{ppn};
        my $query = "
            SELECT
                biblionumber,
                title
            FROM
                biblio
            LEFT JOIN biblioitems USING(biblionumber)
            WHERE $ppn_field = ?
        ";
        my $dbh = C4::Context->dbh;
        $sth = $dbh->prepare($query);
    }
    $sth->execute($ppn);
    my ($biblionumber, $title) = $sth->fetchrow_array;
    $title =~ s/\x88|\x89|\x98|\x9c//g;
    {
        biblionumber => $biblionumber,
        title        => $title,
    };
}

sub get_bibliocontrol {
    my ($self, $rcr) = @_;

    my $c   = $self->config();
    my $api = $c->{url}->{api};
    my $ua  = $self->{ua} ||= Mojo::UserAgent->new;
    my $url = "$api/bibliocontrol/$rcr";
    # Le service web renvoie un fichier en UTF-16LE
    my $res = $ua->get($url)->result->body;
    $res = decode('UTF-16LE', $res);
    my @lines = split /\n/, $res;
    shift @lines;
    my %per_ppn;
    my %errors;
    {
        my @err = @{$conf->{bibliocontrol}->{errors}};
        for (my $i=0; $i < @err; $i++) {
            $errors{$err[$i]} = $i;
        }
    }

    for my $line (@lines) {
        $line =~ s/\r$//;
        my ($ppn, undef, $what) = split /\t/, $line;
        $ppn = substr($ppn, 2, length($ppn)-3);
        $per_ppn{$ppn} ||= [0, 0, 0];
        $per_ppn{$ppn}->[$errors{$what}] = 1;
    }
    my @bibs = map {
        my $ppn = $_;
        my $bib = $self->get_biblio_per_ppn($ppn);
        $bib->{ppn} = $ppn;
        $bib->{ctrl} = $per_ppn{$ppn};
        $bib;
    } keys %per_ppn;
    # Tri par biblionumber
    @bibs = sort { $b->{ppn} <=> $a->{ppn} } @bibs;
    return \@bibs;
}

sub get_algo {
    my ($self, $rcr, $tdoc) = @_;

    my $c   = $self->config();
    my $api = $c->{url}->{algo};
    my $ua  = $self->{ua} ||= Mojo::UserAgent->new;
    my $url = "$api?rcr=" . join(',', @$rcr) . '&typdoc=' . join(',', @$tdoc);
    my $res = $ua->get($url)->result->body;
    #$res = decode('UTF-16LE', $res);
    my @lines = split /\n/, $res;
    shift @lines; shift @lines; shift @lines;
    my %per_ppn;
    for my $line (@lines) {
        $line =~ s/\r$//;
        my ($ppn, undef, $rcr, undef, $date, $where, $tdoc) = split /\t/, $line;
        $where = substr($where, 1);
        $per_ppn{$ppn} ||= {
            rcr  => $rcr,
            tdoc => $tdoc,
            date => substr($date, 0, 10), where => [] };
        push @{ $per_ppn{$ppn}->{where} }, $where;
    }

    my @recs = map {
        my $ppn = $_;
        my $rec = $per_ppn{$ppn};
        $rec->{ppn} = $ppn;
        my $bib = $self->get_biblio_per_ppn($ppn);
        $rec->{title} = $bib->{title};
        $rec->{biblionumber} = $bib->{biblionumber};
        $rec;
    } keys %per_ppn;
    return \@recs;
}

sub intranet_js {
    my $self = shift;
    my $js_file = $self->get_plugin_http_path() . "/abesws.js";
    my $c = encode_json($self->config());
    return <<EOS;
<script>
\$(document).ready(() => {
  \$.getScript("$js_file")
    .done(() => \$.abesWs($c));
});
</script>
EOS
}

sub opac_js {
  shift->intranet_js();
}

sub api_namespace {
    my ($self) = $_;
    return 'abesws';
}

sub api_routes {
    my $self = shift;
    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub install() {
    my ($self, $args) = @_;
}

sub upgrade {
    my ($self, $args) = @_;

    my $dt = DateTime->now();
    $self->store_data( { last_upgraded => $dt->ymd('-') . ' ' . $dt->hms(':') } );

    return 1;
}

sub uninstall() {
    my ($self, $args) = @_;
}

1;
