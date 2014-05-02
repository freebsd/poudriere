// vim: set sts=4 sw=4 ts=4 noet:
var updateInterval = 8;
var first_run = true;

function update_fields() {
	$.ajax({
		url: '.data.json',
		dataType: 'json',
		success: function(data) {
			process_data(data);
		},
		error: function(data) {
			/* May not be there yet, try again shortly */
			setTimeout(update_fields, 2 * 1000);
		}
	});
}

function format_origin(origin) {
	var data;

	if (!origin) {
		return '';
	}

	data = origin.split("/");

	return "<a target=\"_new\" title=\"portsmon for " + origin +
		"\" href=\"http://portsmon.freebsd.org/portoverview.py?category=" +
		data[0] + "&amp;portname=" + data[1] + "\"><i " +
		"class=\"icon-share-alt\"></i>"+ data[0] + "/&#8203;" + data[1] + "</a>";
}

function format_pkgname(pkgname) {
	return pkgname;
}

function minidraw(x, height, width, context, color, queued, variable) {
	var pct, newx;

	pct = variable * 100 / queued;
	if (pct > 98.0 && pct < 100.0) {
		pct = 98;
	} else {
		pct = Math.ceil(pct);
		if (pct == 0) {
			return 0;
		}
	}
	newx = pct * 5;
	if (newx == 0) {
		newx = 1;
	}
	if ((x + newx) >= width) {
		newx = width - x;
	}
	context.fillStyle = color;
	context.fillRect(x, 1, newx, height);

	return (newx);
}

function update_canvas(stats) {
	var queued = stats.queued;
	var built = stats.built;
	var failed = stats.failed;
	var skipped = stats.skipped;
	var ignored = stats.ignored;
	var remaining = queued - built - failed - skipped - ignored;
	var height, width, x, context, canvas;

	height = 10;
	width = 500;

	canvas = document.getElementById('progressbar');
	if (canvas.getContext === undefined) {
		/* Not supported */
		return;
	}

	context = canvas.getContext('2d');

	context.beginPath();
	context.rect(0, 0, width, height);
	/* Save 2 pixels for border */
	height = height - 2;
	/* Start at 1 and save 1 for border */
	width = width - 1;
	x = 1;
	context.fillStyle = '#E3E3E3';
	context.fillRect(1, 1, width, height);
	context.lineWidth = 1;
	context.strokeStyle = 'black';
	context.stroke();
	x += minidraw(x, height, width, context, "#00CC00", queued, built);
	x += minidraw(x, height, width, context, "#E00000", queued, failed);
	x += minidraw(x, height, width, context, "#FF9900", queued, ignored);
	x += minidraw(x, height, width, context, "#CC6633", queued, skipped);

	$('#stats_remaining').html(remaining);
}

function format_log(pkgname, errors, text) {
	var html;

	html = '<a target="logs" href="logs/' + (errors ? 'errors/' : '') +
		pkgname + '.log"><i class="icon-share-alt"></i>' + text + '</a>';
	return html;
}

function format_status_row(status, row) {
	var table_row = [];

	if (status == "built") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin));
		table_row.push(format_log(row.pkgname, false, "logfile"));
	} else if (status == "failed") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin));
		table_row.push(row.phase);
		table_row.push(row.skipped_cnt);
		table_row.push(format_log(row.pkgname, true, row.errortype));
	} else if (status == "skipped") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin));
		table_row.push(format_pkgname(row.depends));
	} else if (status == "ignored") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin));
		table_row.push(row.skipped_cnt);
		table_row.push(row.reason);
	}

	return table_row;
}

function format_setname(setname) {
	return setname ? ('-' + setname) : '';
}

function process_data(data) {
	var html, a, n;
	var table_rows, table_row, main_status;

	// Redirect from /latest/ to the actual build.
	if (document.location.href.indexOf('/latest/') != -1) {
		document.location.href =
			document.location.href.replace('/latest/', '/' + 
			data.buildname + '/');
		return;
	}

	if (data.stats) {
		update_canvas(data.stats);
	}

	document.title = 'Poudriere bulk results for ' + data.mastername +
		data.buildname;

	$('#mastername').html('<a href="../">' + data.mastername + '</a>');
	$('#buildname').html('<a href="#top">' + data.buildname + '</a>');
	if (data.svn_url)
		$('#svn_url').html(data.svn_url);
	else
		$('#svn_url').hide();

	/* Builder status */
	table_rows = [];
	for (n = 0; n < data.status.length; n++) {
		var builder = data.status[n];
		table_row = [];
		table_row.push(builder.id);

		a = builder.status.split(":");

		if (builder.id == "main") {
			main_status = a[0];
		} else {
			a[1] = format_origin(a[1]);
		}

		table_row.push(a[1]);
		table_row.push(a[0]);
		table_rows.push(table_row);

	}
	// XXX This could be improved by updating cells in-place
	$('#builders_table').dataTable().fnClearTable();
	$('#builders_table').dataTable().fnAddData(table_rows);

	/* Stats */
	if (data.stats) {
		$.each(data.stats, function(status, count) {
			$('#stats_' + status).html(count);
		});
	}

	/* For each status, track how many of the existing data has been
	 * added to the table. On each update, only append new data. This
	 * is to lessen the amount of DOM redrawing on -a builds that
	 * may involve looping 24000 times. */

	if (data.ports) {
		$.each(data.ports, function(status, ports) {
			if (data.ports[status] && data.ports[status].length > 0) {
				table_rows = [];
				if ((n = $('#' + status + '_body').data('index')) === undefined) {
					n = 0;
					$('#' + status).show();
					$('#nav_' + status).removeClass('disabled');
				}
				if (n == data.ports[status].length) {
					return;
				}
				for (; n < data.ports[status].length; n++) {
					var row = data.ports[status][n];
					// Add in skipped counts for failures and ignores
					if (status == "failed" || status == "ignored")
						row.skipped_cnt =
							(data.skipped && data.skipped[row.pkgname]) ?
							data.skipped[row.pkgname] :
							0;

					table_rows.push(format_status_row(status, row));
				}
				$('#' + status + '_body').data('index', n);
				$('#' + status + '_table').dataTable().fnAddData(table_rows);
			}
		});
	}

	if (first_run == false) {
		$('.new').fadeIn(1500).removeClass('new');
	} else {
		// Hide loading overlay
		$('#loading_overlay').fadeOut(1400);
		/* Now that page is loaded, scroll to anchor. */
		if (location.hash) {
			$(document).scrollTop($(location.hash).offset().top);
		}
	}

	first_run = false;
	// Refresh as long as the build is not stopped
	if (main_status != "stopped") {
		setTimeout(update_fields, updateInterval * 1000);
	}
}

$(document).ready(function() {
	var columnDefs, status, types, i;

	// Enable LOADING overlay until the page is loaded
	$('#loading_overlay').show();
	$('#builders_table').dataTable({
		"bFilter": false,
		"bInfo": false,
		"bPaginate": false,
	});

	columnDefs = {
		"built": [
			// Disable sorting/searching on 'logfile' link
			{"bSortable": false, "aTargets": [2]},
			{"bSearchable": false, "aTargets": [2]},
		],
		"failed": [
			// Skipped count is numeric
			{"sType": "numeric", "aTargets": [3]},
		],
		"skipped": [],
		"ignored": [
			// Skipped count is numeric
			{"sType": "numeric", "aTargets": [2]},
		],
	};

	types = ['built', 'failed', 'skipped', 'ignored'];
	for (i in types) {
		status = types[i];
		$('#' + status).hide();
		$('#' + status + '_table').dataTable({
			"aaSorting": [], // No initial sorting
			"processing": true, // Show processing icon
			"deferRender": true, // Defer creating TR/TD until needed
			"aoColumnDefs": columnDefs[status],
			"localStorage": true, // Enable cookie for keeping state
			"lengthMenu":[[5,10,25,50,100,200, -1],[5,10,25,50,100,200,"All"]],
			"pageLength": 10,
		});
	}

	update_fields();
});

$(document).bind("keydown", function(e) {
	/* Disable F5 refreshing since this is AJAX driven. */
	if (e.which == 116) {
		e.preventDefault();
	}
});
