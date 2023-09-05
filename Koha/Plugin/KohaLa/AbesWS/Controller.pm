package Koha::Plugin::KohaLa::AbesWS::Controller;

use Modern::Perl;
use utf8;
use Koha::Cache;
use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Koha::Plugin::KohaLa::AbesWS;
use Search::Elasticsearch;
use YAML;

use Mojo::Base 'Mojolicious::Controller';

sub get {
    my $c = shift->openapi->valid_input or return;

    my $logger = Koha::Logger->get({ interface => 'api' });
    my $plugin = Koha::Plugin::KohaLa::AbesWS->new;
    my $pc  = $plugin->config();

    my $author_ppn = $c->validation->param('ppn');
    my $cache = $plugin->{cache};
    my $cache_key = "abes-biblio-$author_ppn";
    my $publications = $cache->get_from_cache($cache_key);
	my $render = sub {
		$c->render(
			status  => 200,
			openapi => {
				status => 'ok',
				reason => '',
				errors => [],
			},
            json => $publications,
		);
	};
    if ($publications) {
        $logger->warn("récup dans le cache\n");
        return $render->();
    }
	$publications = { name => '', ppn => $author_ppn, roles => [] };

	my $ua = Mojo::UserAgent->new;
	$ua = $ua->connect_timeout(15);
	my $url = "https://www.idref.fr/services/biblio/$author_ppn.json";
    $logger->warn("get $url");
	my $response = $ua->get($url)->result;
    if (!$response->is_success) {
        $logger->warn(Dump($response->message));
        return $render->();
    }

	my $json = $response->json;
	my $result = $json->{sudoc}->{result};
	return $render->() if $result->{countRoles} == 0;

	$logger->warn("On requête ES");
	$publications->{name} = $result->{name};
	$result->{role} = [ $result->{role} ] if ref($result->{role}) ne 'ARRAY';
	my $ppn;
	for my $r (@{$result->{role}}) {
		my $role = {
			code => $r->{unimarcCode},
			label => $r->{roleName},
			docs => [],
		};
		$r->{doc} = [ $r->{doc} ] if ref $r->{doc} ne 'ARRAY';
		for my $doc ( @{$r->{doc}} ) {
			push @{$role->{docs}}, {
				ppn => $doc->{ppn},
				citation => $doc->{citation},
			};
			push @$ppn, $doc->{ppn};
		}
		push @{$publications->{roles}}, $role;
	}

	my $ec = C4::Context->config('elasticsearch');
	my $e = Search::Elasticsearch->new( nodes => $ec->{server} );
	my $query = {
		index => $ec->{index_name} . '_biblios',
		body => {
			_source => ["ppn"],
			size => '10000',
			query => { terms => { ppn => $ppn } }
		}
	};
    $logger->warn(join(' ', @$ppn));
	my $res = $e->search($query);
    $logger->warn('retour query ES');
	my $hits = $res->{hits}->{hits};
	my $ppn_to_bib;
	for my $hit (@$hits) {
		my $ppn = $hit->{_source}->{ppn}->[0];
		$ppn_to_bib->{$ppn} = $hit->{_id};
	}
	for my $role (@{$publications->{roles}}) {
		my @docs = @{$role->{docs}};
		for my $d (@docs) {
			my $bib = $ppn_to_bib->{ $d->{ppn} };
			$d->{bib} = $bib if $bib;
		}
		my $key = sub {
			my $doc = shift;
			($doc->{bib} ? 'a' : 'b') . $doc->{citation};
		};
		@docs = sort { $key->($a) cmp $key->($b) } @docs;
		$role->{docs} = \@docs;
	}
    $cache->set_in_cache($cache_key, $publications, { expiry => 100000 });
	
	$render->();
}


1;
