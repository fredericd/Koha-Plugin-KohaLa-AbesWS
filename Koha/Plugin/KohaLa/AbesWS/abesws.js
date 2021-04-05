(function( jQuery, undefined ) {

// Local configuration
let c;

function getBibsFromPpn(ppn, cb) {
  const url = c.url.api + "/multiwhere/" + ppn + '&format=text/json';
  jQuery.getJSON(url)
    .done((data) => {
      let bibs = data?.sudoc?.query?.result?.library;
      if (!Array.isArray(bibs)) bibs = [ bibs ];
      const bibPerRcr = c.iln.rcr_hash;
      bibs.forEach((bib) => {
        bib.itsme = bibPerRcr[bib.rcr] ? true : false;
        bib.sortname = bib.itsme ? ' ' + bib.shortname : bib.shortname;
      });
      bibs = bibs.sort((a, b) => a.sortname.localeCompare(b.sortname));
      cb(bibs);
    });
}

function pageDetail() {
  if ( c.detail.location ) {
    var tabMenu = "<li class='ui-state-default ui-corner-top' role='tab' tabindex='-1' aria-controls='sudoc_tab' aria-labelledby='ui-id-7' aria-selected='false'><a href='#sudoc_tab' class='ui-tabs-anchor' role='presentation' tabindex='-1' id='ui-id-20'>Sudoc</a></li>";
    var tabs = $('#bibliodetails').tabs();
    var ul = tabs.find("ul");
    $(ul).append(tabMenu);
    $(tabs).append('<div id="sudoc_tab"  aria-labelledby="ui-id-20" class="ui-tabs-panel ui-widget-content ui-corner-bottom" role="tabpanel" aria-hidden="true" style="display: none;"></div>');
    tabs.tabs("refresh");
    const ppn = $(c.detail.ppn_selector).text();
    getBibsFromPpn(ppn, (bibs) => {
      let html = '<div style="padding-top:10px;">' +
      '<h4><img src="http://www.sudoc.abes.fr/~c_psi/psi_images/img_psi/3.0/icons/sudoc.png"/> Localisation</h4>' +
      '<ul>' +
      bibs.map((bib) => {
        let style = bib.itsme
          ? "background: green; color: white;"
          : '';
        let shortname = '<a href="http://www.sudoc.abes.fr/cbs/xslt//DB=2.1/SET=1/TTL=1/CLK?IKT=8888&TRM='
          + bib.rcr + '" target="_blank" style="' + style + '">' + bib.shortname + '</a>';
        return '<li>' + shortname + '</li>'
      }).join('') +
      '</ul></div>';
      $('#sudoc_tab').append(html);
      tabs.tabs("refresh");
      $('#ui-id-20').css('font-weight','bold').css('color','green');
    });
  }
}

function run(conf) {
  c = conf;
  if (c.detail.enabled && $('body').is("#catalog_detail")) {
    pageDetail();
  }
}

$.extend({
  abesWs: (c) => run(c),
});


})( jQuery );