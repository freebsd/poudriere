// vim: set sts=4 sw=4 ts=4 noet:
var updateInterval = 8;
var first_run = true;

var show = {
	success: false,
	failed: false,
	skipped: false,
	ignored: false,
	builders: true
}

/* Disabling jQuery caching */
$.ajaxSetup({
	cache: false
});

function minidraw(x, context, color, queued, variable) {
	var pct = variable * 100 / queued;
	if (pct > 98.0 && pct < 100.0) {
		pct = 98;
	} else {
		pct = Math.ceil(pct);
	}
	var newx = pct * 5;
	context.fillStyle = color;
	context.fillRect(x + 1, 1, newx, 20);

	return (newx);
}


function toggle(status) {
	show[status] = !show[status];
	$('#' + status).toggle();
}

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
	var data = origin.split("/");
	return "<a title=\"portsmon for " + origin +
		"\" href=\"http://portsmon.freebsd.org/portoverview.py?category=" +
		data[0] + "&amp;portname=" + data[1] + "\">"+ origin + "</a></td>";
}

function format_pkgname(pkgname) {
	return pkgname;
}

function update_canvas(stats) {
	var queued = stats.queued;
	var built = stats.built;
	var failed = stats.failed;
	var skipped = stats.skipped;
	var ignored = stats.ignored;
	var remaining = queued - built - failed - skipped - ignored;

	var canvas = document.getElementById('progressbar');
	if (canvas.getContext === undefined) {
		/* Not supported */
		return;
	}

	var context = canvas.getContext('2d');

	context.beginPath();
	context.rect(0, 0, 502, 22);
	context.fillStyle = '#E3E3E3';
	context.fillRect(1, 1, 500, 20);
	context.lineWidth = 1;
	context.strokeStyle = 'black';
	context.stroke();
	var x = 0;
	x += minidraw(x, context, "#00CC00", queued, built);
	x += minidraw(x, context, "#E00000", queued, failed);
	x += minidraw(x, context, "#FF9900", queued, ignored);
	x += minidraw(x, context, "#CC6633", queued, skipped);

	$('#stats_remaining').html(remaining);
}

function format_log(pkgname, errors, text) {
	var html;

	html = '<a href="logs/' + (errors ? 'errors/' : '') +
		pkgname + '.log">' + text + '</a>';
	return html;
}

function format_status_row(status, row) {
	var html = '';

	if (status == "built") {
		html += "<td>" + format_pkgname(row.pkgname) + "</td>";
		html += "<td>" + format_origin(row.origin) + "</td>";
		html += "<td>" + format_log(row.pkgname, false, "logfile") + "</td>";
	} else if (status == "failed") {
		html += "<td>" + format_pkgname(row.pkgname) + "</td>";
		html += "<td>" + format_origin(row.origin) + "</td>";
		html += "<td>" + row.phase + "</td>";
		html += "<td>" + row.skipped_cnt + "</td>";
		html += "<td>" + format_log(row.pkgname, true, "logfile") + "</td>";
	} else if (status == "skipped") {
		html += "<td>" + format_pkgname(row.pkgname) + "</td>";
		html += "<td>" + format_origin(row.origin) + "</td>";
		html += "<td>" + format_pkgname(row.depends) + "</td>";
	} else if (status == "ignored") {
		html += "<td>" + format_pkgname(row.pkgname) + "</td>";
		html += "<td>" + format_origin(row.origin) + "</td>";
		html += "<td>" + row.skipped_cnt + "</td>";
		html += "<td>" + row.reason + "</td>";
	}

	return html;
}

function format_setname(setname) {
	return setname ? ('-' + setname) : '';
}

function process_data(data) {
	var html, a, n;

	if (data.stats) {
		update_canvas(data.stats);
	}

	document.title = 'Poudriere bulk results for ' + data.jail +
		format_setname(data.setname) + '-' + data.ptname + ' ' +
		data.buildname;

	$('#jail').html(data.jail);
	$('#setname').html(data.setname);
	$('#ptname').html(data.ptname);
	$('#buildname').html(data.buildname);

	/* Builder status */
	html = '';
	for (n = 0; n < data.status.length; n++) {
		var builder = data.status[n];
		html += "<tr><td>" + builder.id + "</td>";

		a = builder.status.split(":");
		html += "<td>" + format_origin(a[1]) + "</td>";
		html += "<td>" + a[0] + "</td></tr>";
	}
	$('#builders_body').html(html);

	/* Stats */
	if (data.stats) {
		$.each(data.stats, function(status, count) {
			if (status == "queued") {
				html = count;
			} else {
				html = '<a href="#' + status + '">' + count + '</a>';
			}

			$('#stats_' + status).html(html);
		});
	}

	/* For each status, track how many of the existing data has been
	 * added to the table. On each update, only append new data. This
	 * is to lessen the amount of DOM redrawing on -a builds that
	 * may involve looping 24000 times. */

	if (data.ports) {
		$.each(data.ports, function(status, ports) {
			if (data.ports[status] && data.ports[status].length > 0) {
				html = '';
				if ((n = $('#' + status + '_body').data('index')) === undefined) {
					n = 0;
				}
				for (; n < data.ports[status].length; n++) {
					var row = data.ports[status][n];
					var even = ((n % 2) == 0) ? '1' : '0';
					// Add in skipped counts for failures and ignores
					if (status == "failed" || status == "ignored")
						row.skipped_cnt =
							(data.skipped && data.skipped[row.pkgname]) ?
							data.skipped[row.pkgname] :
							'';
					html += '<tr class="' + (first_run ? '' : 'new ') +
						'row' + even + ' "' +
						' >' + format_status_row(status, row) + '</tr>';
				}
				$('#' + status + '_body').append(html);
				$('#' + status + '_body').data('index', n);
			}
		});
	}

	if (first_run == false) {
		$('.new').fadeIn(1500).removeClass('new');
	} else {
		// Hide loading overlay
		$('#loading_overlay').fadeOut(1400);
	}

	first_run = false;
	setTimeout(update_fields, updateInterval * 1000);
}

$(document).ready(function() {
	// Enable LOADING overlay until the page is loaded
	$('#loading_overlay').show();	
	update_fields();
	$("form input").each(function(){
		var elem = $(this);
		var type = elem.attr("type");
		if (type == "checkbox" && elem.attr("id") != "builders_check") {
			elem.prop("checked", "");
		}
	});

});

$(document).bind("keydown", function(e) {
	/* Disable F5 refreshing since this is AJAX driven. */
	if (e.which == 116) {
		e.preventDefault();
	}
});
