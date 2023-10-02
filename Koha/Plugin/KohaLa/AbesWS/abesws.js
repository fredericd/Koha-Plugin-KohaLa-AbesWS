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
    const ppn = $(c.detail.ppn_selector).text();
    if (ppn === '') {
      console.log('PPN non trouvé. Manque-t-il le sélecteur PPN ?');
      return;
    }
    $('.nav-tabs').append(`
      <li role="presentation">
        <a href="#sudoc" aria-controls="sudoc" role="tab" data-toggle="tab" aria-expanded="false">Sudoc</a>
      </li>
    `);
    $('#bibliodetails .tab-content').append(`
      <div role="tabpanel" class="tab-pane" id="sudoc">
        <div id="sudoc-content"></div>
      </div>
    `);
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
      $('#sudoc-content').html(html);
    });
  }
}

function opacDetail() {
  $('span.idref-link').each(function(index){
    const ppn = $(this).attr('ppn');
    const html = `
      <a class="idref-link-click" style="cursor: pointer;" ppn="${ppn}" title="See publications in IdRef">
        <img src="/plugin/Koha/Plugin/KohaLa/AbesWS/img/idref-short.svg" width="5%">
      </a>`;
    $(this).html(html);
  });
  $('.idref-link-click').click(function(){
    const ppn = $(this).attr('ppn');
    const url = `/api/v1/contrib/abesws/biblio/${ppn}`;
    jQuery.getJSON(url)
      .done((publications) => {
        let html;
        if (publications.name === '') {
          html = __('Author not found in IdRef');
        } else {
          const navig = publications.roles.map(role => `<a href="#idref-role-${role.code}" style="font-size: 90%;">${role.label} (${role.docs.length})</a>`);
          let html_notes = '';
          if (publications.notes) {
            html_notes = `
              <div style="font-size:100%; margin-bottom: 3px;">
                ${publications.notes.join('<br/>')}
              </div>`;
          }
          html = `
            <h2>
              ${publications.name} / <small>
              <a href="https://www.idref.fr/${publications.ppn}" target="_blank">${publications.ppn}</a>
              </small>
            </h2>
            ${html_notes}
            <div style="margin-bottom: 5px;";>${navig.join(' • ')}</div>`;
          publications.roles.forEach((role) => {
            html += `
              <h3 id="idref-role-${role.code}">${role.label}</h3>
              <table class="table table-striped table-hover table-sm"><tbody>`;
            role.docs.forEach((doc) => {
              html += `
                <tr>
                  <td>
                  <a href="https://www.sudoc.fr/${doc.ppn}" target="_blank" rel="noreferrer">
                  <img title="` + __('Publication In Sudoc Catalog') + `" src="/plugin/Koha/Plugin/KohaLa/AbesWS/img//sudoc.png" />
                  </a>`;
              if (doc.bib) {
                html += `
                  <a href="/cgi-bin/koha/opac-detail.pl?biblionumber=${doc.bib}" target="_blank">
                  <img title="` + __('Publication In Local Catalog') + `" src="/opac-tmpl/bootstrap/images/favicon.ico" />
                  </a>`;
              }
              html += `</td><td>${doc.citation}</td></tr>`;
            });
            html += '</tbody></table>';
          });
          html += '</div>';
        }
        const idrefDiv = $('#idref-publications');
        if (idrefDiv.length) {
          idrefDiv.html(html);
        } else {
          html = `<div id="idref-publications">${html}</div>`;
          $('.nav-tabs').append(`
            <li id="tab_idref" class="nav-item" role="presentation">
             <a href="#idref-publications" class="nav-link" id="tab_idref-tab"
                data-toggle="tab" role="tab" aria-controls="tab_idref" aria-selected="false"
             >
               <img src="/plugin/Koha/Plugin/KohaLa/AbesWS/img/idref.svg" style="height: 20px;"/>
             </a>
            </li>
          `);
          $('#bibliodescriptions .tab-content').append(`
            <div id="idref-publications" class="tab-pane" role="tabpanel" aria-labelledby="tab_idref-tab">
              ${html}
            <div>
          `);
        }
        $('a[href="#idref-publications"]').click();
        $([document.documentElement, document.body]).animate({
          scrollTop: $("#idref-publications").offset().top
        }, 2000);
      });
    });
}

function run(conf) {
  c = conf;
  if (c?.detail?.enabled && $('body').is("#catalog_detail")) {
    pageDetail();
  } else if (c?.opac?.publication?.enabled && $('body').is('#opac-detail')) {
    opacDetail();
  }

}

$.extend({
  abesWs: (c) => run(c),
});


})( jQuery );
