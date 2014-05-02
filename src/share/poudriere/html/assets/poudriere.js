// vim: set sts=4 sw=4 ts=4 noet:
var updateInterval = 8;
var first_run = true;
var canvas_width;
var impulseData = [];
var tracker = 0;
var impulse_first_period =		120;
var impulse_target_period =		600;
var impulse_period =			impulse_first_period;
var impulse_first_interval =	impulse_first_period / updateInterval;
var impulse_interval = 			impulse_target_period / updateInterval;

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
		data[0] + "&amp;portname=" + data[1] + "\"><span " +
		"class=\"glyphicon glyphicon-tasks\"></span>"+ origin + "</a>";
}

function format_pkgname(pkgname) {
	return pkgname;
}

function minidraw(x, height, width, context, color, queued, variable) {
	var pct, total_pct, newx;

	/* Calculate how much percentage this value should display */
	pct = Math.floor(variable * 100 / queued);
	if (pct == 0) {
		return 0;
	}
	newx = width * (pct / 100);
	if ((x + newx) >= width) {
		newx = width - x;
	}
	/* Cap total bar to 99% so it's clear something is remaining */
	total_pct = ((x + newx) / width) * 100;
	if (total_pct >= 99.0 && total_pct < 100.0) {
		newx = (Math.ceil(width * (99 / 100)));
	}
	/* Always start at 1 */
	if (newx == 0) {
		newx = 1;
	}
	context.fillStyle = color;
	context.fillRect(x, 1, newx, height);

	return (newx);
}

function determine_canvas_width() {
	var width;

	/* Determine width by how much space the column has, minus the size of
	 * displaying the percentage at 100%
	 */
	width = $('#progress_col').width();
	$('#progresspct').text('100%');
	width = width - $('#progresspct').width() - 20;
	$('#progresspct').text('');
	canvas_width = width;
}

function update_canvas(stats) {
	var queued, built, failed, skipped, ignored, remaining, pctdone;
	var height, width, x, context, canvas;

	if (stats.queued === undefined) {
		return;
	}

	canvas = document.getElementById('progressbar');
	if (canvas.getContext === undefined) {
		/* Not supported */
		return;
	}

	height = 10;
	width = canvas_width;

	canvas.height = height;
	canvas.width = width;

	queued = stats.queued;
	built = stats.built;
	failed = stats.failed;
	skipped = stats.skipped;
	ignored = stats.ignored;
	remaining = queued - built - failed - skipped - ignored;

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

	pctdone = Math.floor(((queued - remaining) * 100) / queued);
	$('#progresspct').text(pctdone + '%');

	$('#stats_remaining').html(remaining);
}

function display_pkghour(stats) {
	var attempted, pkghour, hours;

	attempted = parseInt(stats.built) + parseInt(stats.failed);
	pkghour = "--";
	if (attempted > 0) {
		hours = stats.elapsed / 3600;
		pkghour = Math.ceil(attempted / hours);
	}
	$('#stats_pkghour').html(pkghour);
}

function display_impulse(stats) {
	var attempted, pkghour, index, tail, d_pkgs, d_secs, title;

	attempted = parseInt(stats.built) + parseInt(stats.failed);
	pkghour = "--";
	index = tracker % impulse_interval;
	if (tracker < impulse_interval) {
		impulseData.push({pkgs: attempted, time: stats.elapsed});
	} else {
		impulseData[index].pkgs = attempted;
		impulseData[index].time = stats.elapsed;
	}
	if (tracker >= impulse_first_interval) {
		if (tracker < impulse_interval) {
			tail = 0;
			title = "Package build rate over last " + Math.floor((tracker * updateInterval)/60) + " minutes";
		} else {
			tail = (tracker - (impulse_interval - 1)) % impulse_interval;
			title = "Package build rate over last " + (impulse_target_period/60) + " minutes";
		}
		d_pkgs = impulseData[index].pkgs - impulseData[tail].pkgs;
		d_secs = impulseData[index].time - impulseData[tail].time;
		pkghour = Math.ceil(d_pkgs / (d_secs / 3600));
	} else {
		title = "Package build rate. Still calculating..."
	}
	tracker++;
	$('#system .impulse').attr('title', title);
	$('#stats_impulse').html(pkghour);
}

function format_log(pkgname, errors, text) {
	var html;

	html = '<a target="logs" title="Log for ' + pkgname + '" href="logs/' + (errors ? 'errors/' : '') +
		pkgname + '.log"><span class="glyphicon glyphicon-file"></span>' + text + '</a>';
	return html;
}

function format_duration(start, end) {
    var duration, hours, minutes, seconds;

	if (end === undefined) {
		duration = start;
	} else {
		duration = end - start;
	}

    hours = Math.floor(duration / 3600);
    duration = duration - hours * 3600;
    minutes = Math.floor(duration / 60);
    seconds = duration - minutes * 60;

    if (hours < 10) {
        hours = '0' + hours;
    }
    if (minutes < 10) {
        minutes = '0' + minutes;
    }
    if (seconds < 10) {
        seconds = '0' + seconds;
    }

    return hours + ':' + minutes + ':' + seconds;
}

function filter_skipped(pkgname) {
	var table, search_filter;

	$(document).scrollTop($('#skipped').offset().top);
	table = $('#skipped_table').dataTable();
	table.fnFilter(pkgname, 2);

	search_filter = $('#skipped_table_filter input');
	search_filter.val(pkgname);
	search_filter.prop('disabled', true);
	search_filter.css('background-color', '#DDD');

	if (!$('#resetsearch').length) {
		search_filter.after('<span class="glyphicon glyphicon-remove ' +
				'pull-right" id="resetsearch"></span>');

		$("#resetsearch").click(function(e) {
			table.fnFilter('', 2);
			search_filter.val('');
			search_filter.prop('disabled', false);
			search_filter.css('background-color', '');
			$(this).remove();
		});
	}
}

function format_status_row(status, row) {
	var table_row = [];
	var skipped_cnt;

	if (row.skipped_cnt !== undefined && row.skipped_cnt > 0) {
		skipped_cnt = row.skipped_cnt;
		row.skipped_cnt = '<a href="#skipped" onclick="filter_skipped(\'' +
			row.pkgname +'\'); return false;"><span class="glyphicon ' +
			'glyphicon-filter"></span>' + skipped_cnt + '</a>';
	}

	if (status == "built") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin));
		table_row.push(format_log(row.pkgname, false, 'success'));
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
	var table_rows, table_row, main_status, builder, now;

	now = Math.floor(new Date().getTime() / 1000);

	// Redirect from /latest/ to the actual build.
	if (document.location.href.indexOf('/latest/') != -1) {
		document.location.href =
			document.location.href.replace('/latest/', '/' + 
			data.buildname + '/');
		return;
	}

	if (data.stats) {
		determine_canvas_width();
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
	$('#build_info').show();

	/* Builder status */
	table_rows = [];
	for (n = 0; n < data.status.length; n++) {
		builder = data.status[n];

		if (builder.id != "main") {
			table_row = [];
			table_row.push(builder.id);
			table_row.push(builder.origin ? format_origin(builder.origin) : "");
			table_row.push(builder.pkgname ? format_log(builder.pkgname, false, builder.status) : builder.status.split(":")[0]);
			table_row.push(builder.started ? format_duration(builder.started, now) : "");
			table_rows.push(table_row);
		} else {
			a = builder.status.split(":");
			if (a[0] == "stopped") {
				if (a.length >= 3) {
					main_status = a[0] + ':' + a[1] + ':' + a[2];
				} else if (a.length >= 2) {
					main_status = a[0] + ':' + a[1];
				} else {
					main_status = a[0] + ':';
				}
			} else {
				if (a.length >= 2) {
					main_status = a[0] + ':' + a[1];
				} else {
					main_status = a[0] + ':';
				}
			}
			$('#build_status').text(main_status);
		}
	}
	if (table_rows.length) {
		$('#jobs').show();

		// XXX This could be improved by updating cells in-place
		$('#builders_table').dataTable().fnClearTable();
		$('#builders_table').dataTable().fnAddData(table_rows);
	}

	/* Stats */
	if (data.stats) {
		$.each(data.stats, function(status, count) {
			if (status == "elapsed") {
				count = format_duration(count);
			}
			$('#stats_' + status).html(count);
		});
		display_pkghour(data.stats);
		display_impulse(data.stats);
		$('#stats').data(data.stats);
		$('.layout div').fadeIn(1400);
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
	if (!main_status.match("^stopped:")) {
		setTimeout(update_fields, updateInterval * 1000);
	}
}

/* Disable static navbar at the breakpoint */
function do_resize(win) {
	/* Redraw canvas to new width */
	if ($('#stats').data()) {
		determine_canvas_width();
		update_canvas($('#stats').data());
	}
}

/* Force minimum width on mobile, will zoom to fit. */
function fix_viewport() {
	var minimum_width;

	minimum_width = parseInt($('body').css('min-width'));
	if (minimum_width != 0 && window.innerWidth < minimum_width) {
		$('meta[name=viewport]').attr('content','width=' + minimum_width);
	} else {
		$('meta[name=viewport]').attr('content','width=device-width, initial-scale=1.0');
	}
}

$(document).ready(function() {
	var columns, status, types, i;

	$('#builders_table').dataTable({
		"bFilter": false,
		"bInfo": false,
		"bPaginate": false,
		"bAutoWidth": false,
		"aoColumns": [
			// Smaller ID/Status
			{"sWidth": "1em"},
			null,
			{"sWidth": "8em"},
			{"sWidth": "3em"},
		],
	});

	columns = {
		"built": [
			null,
			null,
			{
				"sWidth": "4.25em",
				"bSortable": false,
				"bSearchable": false,
			},
		],
		"failed": [
			null,
			null,
			{
				"sWidth": "6em",
			},
			{
				"sType": "numeric",
				"sWidth": "4em",
			},
			{
				"sWidth": "7em",
			},
		],
		"skipped": [
			null,
			null,
			{
				"sWidth": "35em",
			},
		],
		"ignored": [
			null,
			null,
			{
				"sWidth": "4em",
				"sType": "numeric",
			},
			{
				"sWidth": "35em",
			},
		],
	};

	types = ['built', 'failed', 'skipped', 'ignored'];
	for (i in types) {
		status = types[i];
		$('#' + status + '_table').dataTable({
			"aaSorting": [], // No initial sorting
			"bAutoWidth": false,
			"processing": true, // Show processing icon
			"deferRender": true, // Defer creating TR/TD until needed
			"aoColumns": columns[status],
			"localStorage": true, // Enable cookie for keeping state
			"lengthMenu":[[5,10,25,50,100,200, -1],[5,10,25,50,100,200,"All"]],
			"pageLength": 10,
		});
	}

	/* Force minimum width on mobile, will zoom to fit. */
	$(window).bind('orientationchange', function(e) {fix_viewport();});
	fix_viewport();
	/* Handle resize needs */
	$(window).on('resize', function() {do_resize($(this));});
	do_resize($(window));

	update_fields();
});

$(document).bind("keydown", function(e) {
	/* Disable F5 refreshing since this is AJAX driven. */
	if (e.which == 116) {
		e.preventDefault();
	}
});
