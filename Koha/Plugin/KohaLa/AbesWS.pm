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
use JSON qw/ decode_json to_json /;


## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'KohaLa AbesWS',
    description     => 'Utilisation de services web Abes',
    author          => 'Tamil s.a.r.l.',
    date_authored   => '2021-03-31',
    date_updated    => "2021-01-31",
    minimum_version => '20.05.00.000',
    maximum_version => undef,
    copyright       => '2021',
    version         => '1.0.0',
};


my $conf = {
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

my $service = {
    init => sub {

    }
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
    $c->{metadata} = $self->{metadata};

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
        },
        detail => {
            enabled => 0,
            location => 0,
            ppn_selector => undef,
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
        my $rcr = [ split /\n/, $c->{iln}->{rcr} ];
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

    my $cgi = $self->{'cgi'};

    my $template;
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
                $template->param( rcr_select => $self->get_rcr() );
            }
        }
        elsif ($ws eq 'algo') {
            $template = $self->get_template({ file => 'algo.tt' });
            my @rcr = $cgi->multi_param('rcr');
            my @tdoc = $cgi->multi_param('tdoc');
            if (@rcr) {
                my %tdoc_hash;
                for ( (['bib', 'Biblio'], ['aut', 'Autorité']) ) {
                    my ($code, $type) = @$_;
                    my $tdoc = $conf->{algo}->{tdoc}->{$code};
                    for ( keys %$tdoc ) {
                        $tdoc_hash{$_} = "$type: " . $tdoc->{$_};
                    }
                }
                $template->param( rcr_hash => $self->get_rcr_hash() );
                $template->param( tdoc_hash => \%tdoc_hash );
                $template->param( recs => $self->get_algo(\@rcr, \@tdoc) );
            }
            else {
                $template->param( rcr_select => $self->get_rcr() );
                my @tdoc_select;
                for ( (['bib', 'Biblio'], ['aut', 'Autorité']) ) {
                    my ($code, $type) = @$_;
                    my $tdoc = $conf->{algo}->{tdoc}->{$code};
                    for ( keys %$tdoc ) {
                        push @tdoc_select, [$_, "$type: " . $tdoc->{$_}];
                    }
                }
                $template->param( tdoc_select => \@tdoc_select );
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


sub get_rcr {
    my $self = shift;
    my $c = $self->config();
    my @rcr = split /\r|\n/, $c->{iln}->{rcr};
    @rcr = grep { $_ } @rcr;
    @rcr = map {
        /^([0-9]+) +(.+)$/ ? [$1, $2] : [$_, $_];
    } @rcr;
    return \@rcr;
}

sub get_rcr_hash {
    my $self = shift;
    my $rcr = $self->get_rcr();
    my %bib_per_rcr = map { $_->[0] => $_->[1] } @$rcr;
    return \%bib_per_rcr;
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
    my %errors = (
        'une 225 est presente sans 410 ni 461' => 0,
        'une 700 701 702 n a pas de code fonction' => 1,
        'une 181 est presente en meme temps qu une 200$b' => 2,
    );
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
    my $c = $self->config();

    my $bib_per_rcr = $c->{detail}->{enabled}
        ? to_json($self->get_rcr_hash())
        : undef;

    return <<EOS;
<script>
\$(document).ready(() => {
    if ($c->{detail}->{enabled} && \$('body').is("#catalog_detail")) {
        pageDetail();
    }
});

function SortBibs(bibs) {
    const bibPerRcr = JSON.parse('$bib_per_rcr');
    bibs.forEach((bib) => {
        bib.itsme = bibPerRcr[bib.rcr] ? true : false;
        bib.sortname = bib.itsme ? ' ' + bib.shortname : bib.shortname;
    });
    bibs = bibs.sort((a, b) => a.sortname.localeCompare(b.sortname));
    console.log(bibs);
    return bibs;
}

function pageDetail() {
    if ( $c->{detail}->{location} ) {
        var tabMenu = "<li class='ui-state-default ui-corner-top' role='tab' tabindex='-1' aria-controls='sudoc_tab' aria-labelledby='ui-id-7' aria-selected='false'><a href='#sudoc_tab' class='ui-tabs-anchor' role='presentation' tabindex='-1' id='ui-id-20'>Sudoc</a></li>";
        var tabs = \$('#bibliodetails').tabs();
        var ul = tabs.find("ul");
        \$(ul).append(tabMenu);
        \$(tabs).append('<div id="sudoc_tab"  aria-labelledby="ui-id-20" class="ui-tabs-panel ui-widget-content ui-corner-bottom" role="tabpanel" aria-hidden="true" style="display: none;"></div>');
        tabs.tabs("refresh");
        const ppn = \$('$c->{detail}->{ppn_selector}').text();
        const url = "$c->{url}->{api}/multiwhere/" + ppn + '&format=text/json';
        jQuery.getJSON(url)
            .done((data) => {
                let bibs = data?.sudoc?.query?.result?.library;
                if (!Array.isArray(bibs)) bibs = [ bibs ];
                bibs = SortBibs(bibs);
                let html = '<div style="padding-top:10px;">' +
                    '<h4><img src="http://www.sudoc.abes.fr/~c_psi/psi_images/img_psi/3.0/icons/sudoc.png"/> Localisation dans le Sudoc</h4>' +
                    '<ul>' +
                    bibs.map((bib) => {
                        let shortname = '<a href="http://www.sudoc.abes.fr/cbs/xslt//DB=2.1/SET=1/TTL=1/CLK?IKT=8888&TRM='
                            + bib.rcr + '" target="_blank">' + bib.shortname + '</a>';
                        if (bib.itsme) shortname = '<b>' + shortname + '</b>';
                        return '<li>' + shortname + '</li>'
                    }).join('') +
                    '</ul></div>';
                \$('#sudoc_tab').append(html);
                tabs.tabs("refresh");
            });
    }
}

</script>
EOS
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
