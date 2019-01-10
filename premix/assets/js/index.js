var premix = function() {
  function chunkSubstr(str, size) {
    const numChunks = Math.ceil(str.length / size)
    const chunks = new Array(numChunks)

    for (let i = 0, o = 0; i < numChunks; ++i, o += size) {
      chunks[i] = str.substr(o, size)
    }

    return chunks
  }

  function split32(text) {
    if(text.length > 32) {
      let chunks = chunkSubstr(text, 32);
      let result = "";
      for(var x of chunks) {
        result += '<div>'+x+'</div>';
      }
      return result;
    } else {
      return text;
    }
  }

  return {
    fields: ['op', 'pc', 'gas', 'gasCost', 'depth'],

    newTable: function(container) {
      let table = $('<table class="uk-table uk-table-divider"/>').appendTo(container);
      $('<thead><tr><th>Field</th><th>Nimbus</th><th>Geth</th></tr></thead>').appendTo(table);
      return $('<tbody></tbody>').appendTo(table);
    },

    renderRow: function(body, nimbus, geth, x) {
      let row = $('<tr/>').appendTo(body);
      let ncr = nimbus[x].toString().toLowerCase();
      let gcr = geth[x].toString().toLowerCase();
      let cls = ncr == gcr ? '' : 'class="uk-text-danger"';
      $(`<td ${cls}>${split32(x)}</td>`).appendTo(row);
      $(`<td ${cls}>${split32(ncr)}</td>`).appendTo(row);
      $(`<td ${cls}>${split32(gcr)}</td>`).appendTo(row);
    },

    newSection: function(container, title, colored) {
      let section = $('<div class="uk-section uk-section-xsmall tm-horizontal-overflow"></div>').appendTo(container);
      section.addClass(colored ? "uk-section-secondary uk-light" : "uk-section-muted");
      let contentDiv = $('<div class="uk-container uk-margin-small-left uk-margin-small-right"></div>').appendTo(section);
      $(`<h4>${title}</h4>`).appendTo(contentDiv);
      return contentDiv;
    }

  };
}();

function windowResize() {
  let bodyHeight = $(window).height();
  $('#opCodeSideBar').css('height', parseInt(bodyHeight) - 80);
}

function renderTrace(title, nimbus, geth) {
  let container = $('#opCodeContainer').empty();
  let body = premix.newTable(container);
  for(var x of premix.fields) {
    premix.renderRow(body, nimbus, geth, x);
  }

  function renderExtra(name) {
    let nk = Object.keys(nimbus[name]);
    let gk = Object.keys(geth[name]);
    let keys = new Set(nk.concat(gk));

    if(keys.size > 0) {
      let section = premix.newSection(container, name);
      let body = premix.newTable(section);
      for(var key of keys) {
        premix.renderRow(body, nimbus[name], geth[name], key);
      }
      $('<hr class="uk-divider-icon">').appendTo(container);
    }
  }

  renderExtra("memory");
  renderExtra("stack");
  renderExtra("storage");
}

function opCodeRenderer(txId, nimbus, geth) {
  function analyze(nimbus, geth) {
    for(var x of premix.fields) {
      if(nimbus[x] != geth[x]) return false;
    }
    // TODO: analyze stack, storage, mem
    return true;
  }

  txId = parseInt(txId);
  var ncs = nimbus.txTraces[txId].structLogs;
  var gcs = geth.txTraces[txId].structLogs;
  var sideBar = $('#opCodeSideBar').empty();
  $('#opCodeTitle').text(`Tx #${(txId+1)}`);

  for(var i in ncs) {
    var pc = ncs[i];
    if(!analyze(ncs[i], gcs[i])) {
      var nav = $(`<li><a class="tm-text-danger" rel="${i}" href="#">${pc.pc + ' ' + pc.op}</a></li>`).appendTo(sideBar);
    } else {
      var nav = $(`<li><a rel="${i}" href="#">${pc.pc + ' ' + pc.op}</a></li>`).appendTo(sideBar);
    }
    nav.children('a').click(function(ev) {
      let idx = this.rel;
      $('#sideBar li').removeClass('uk-active');
      $(this).parent().addClass('uk-active');
      renderTrace('tx', ncs[idx], gcs[idx]);
    });
  }

  renderTrace("tx", ncs[0], gcs[0]);
  windowResize();
}

function transactionsRenderer(txId, nimbus, geth) {
  $('#transactionsTitle').text(`Tx #${(txId+1)}`);
  let container = $('#transactionsContainer').empty();

  function renderTx(nimbus, geth) {
    let body = premix.newTable(container);
    const fields = ["gas", "returnValue", "cumulativeGasUsed", "bloom"];
    for(var x of fields) {
      premix.renderRow(body, nimbus, geth, x);
    }

    // TODO: receipt logs
  }

  txId = parseInt(txId);
  let ntx = nimbus.txTraces[txId];
  let gtx = geth.txTraces[txId];

  let ncr = $.extend({
    gas: ntx.gas,
    returnValue: ntx.returnValue
  },
    nimbus.receipts[txId]
  );

  let gcr = $.extend({
    gas: gtx.gas,
    returnValue: "0x" + gtx.returnValue
  },
    geth.receipts[txId]
  );

  renderTx(ncr, gcr);
}

function headerRenderer(nimbus, geth) {
  let container = $('#headerContainer').empty();

  let ncs = nimbus.stateDump.after;
  let gcs = geth.accounts;


  for(var n of ncs) {
    n.address = '0x' + n.address;
    n.balance = '0x' + n.balance;
    n.code = '0x' + n.code;
    let g = gcs[n.address];

  }

          /*"name": "internalTx0",
          "address": "0000000000000000000000000000000000000004",
          "nonce": "0000000000000000",
          "balance": "0",
          "codeHash": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
          "code": "",
          "storageRoot": "56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
          "storage": {}*/

        /*"0xf927a40c8b7f6e07c5af7fa2155b4864a4112b13": {
        "balance": "0x607c9cea65ef7e19dd8",
        "nonce": "0000000000000000",
        "code": "0x",
        "storage": {}*/


}

function generateNavigation(txs, nimbus, geth) {
  function navAux(menuId, renderer) {
    let menu = $(menuId).click(function(ev) {
      renderer(0, nimbus, geth);
    });

    if(txs.length == 0) {
      menu.parent().addClass('uk-disabled');
    } else if(txs.length > 1) {
      $('<span uk-icon="icon: triangle-down"></span>').appendTo(menu);
      let div  = $('<div uk-dropdown="mode: hover;"/>').appendTo(menu.parent());
      let list = $('<ul class="uk-nav uk-dropdown-nav"/>').appendTo(div);

      for(var i in txs) {
        let id = i.toString();
        $(`<li class="uk-active"><a rel="${id}" href="#">TX #${id}</a></li>`).appendTo(list);
      }

      list.find('li a').click(function(ev) {
        renderer(this.rel, nimbus, geth);
      });
    }
  }

  navAux('#opCodeMenu', opCodeRenderer);
  navAux('#transactionsMenu', transactionsRenderer);

  $('#headerMenu').click(function(ev) {
    headerRenderer(nimbus, geth);
  });
}

$(document).ready(function() {

  var nimbus = premixData.nimbus;
  var geth = premixData.geth;
  var transactions = geth.block.transactions;

  generateNavigation(transactions, nimbus, geth);
});