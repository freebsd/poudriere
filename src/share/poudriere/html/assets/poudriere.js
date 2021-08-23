// vim: set sts=4 sw=4 ts=4 noet:
/*
 * Copyright (c) 2013-2017 Bryan Drewery <bdrewery@FreeBSD.org>
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

var updateInterval = 8;
var first_run = true;
var load_attempts = 0;
var max_load_attempts = 8;
var first_load_interval = 2;
var canvas_width;
var impulseData = [];
var tracker = 0;
var impulse_first_period =		120;
var impulse_target_period =		600;
var impulse_period =			impulse_first_period;
var impulse_first_interval =	impulse_first_period / updateInterval;
var impulse_interval = 			impulse_target_period / updateInterval;
var page_type;
var page_buildname;
var page_mastername;
var data_url = '';

function getParameterByName(name) {
	name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
	var regex = new RegExp("[\\?&]" + name + "=([^&#]*)"),
		results = regex.exec(location.search);
	return results == null ? "" :
		decodeURIComponent(results[1].replace(/\+/g, " "));
}

function scrollOffset() {
	return -1 * parseFloat($('body').css('padding-top'));
}

function scrollToElement(element) {
	var ele = $(element);
	if (!ele.length) {
		return;
	}
	$('body,html,document').scrollTop(ele.offset().top + scrollOffset());
}

function update_data() {
	$.ajax({
		url: data_url + '.data.json',
		dataType: 'json',
		headers: {
			'Cache-Control': 'max-age=0',
		},
		success: function(data) {
			load_attempts = 0;
			process_data(data);
		},
		error: function(data) {
			if (++load_attempts < max_load_attempts) {
				/* May not be there yet, try again shortly */
				setTimeout(update_data, first_load_interval * 1000);
			} else {
				$('#loading p').text('Invalid request or no data available ' +
					' yet.').addClass('error');
			}
		}
	});
}

function format_origin(origin, flavor) {
	var data;

	if (!origin) {
		return '';
	}

	data = origin.split("/");

	if (flavor) {
		flavor = "@" + flavor;
	} else {
		flavor = '';
	}

	return "<a target=\"_new\" title=\"freshports for " + origin +
		"\" href=\"https://www.freshports.org/" +
		data[0] + "/" + data[1] + "/\"><span " +
		"class=\"glyphicon glyphicon-tasks\"></span>"+ origin + flavor +
		"</a>";
}

function format_githash(githash) {
	if (!githash) {
		return '';
	}
	return "<a target=\"_new\" title=\"cgit for " + githash +
		"\" href=\"https://cgit.freebsd.org/ports/commit/?id=" +
		githash + "\"><span " +
		"class=\"glyphicon glyphicon-envelope\"></span>"+ githash +
		"</a>";
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
	var queued, built, failed, skipped, ignored, fetched, remaining, pctdone;
	var height, width, x, context, canvas, pctdonetxt;

	if (stats.queued === undefined) {
		return;
	}

	canvas = document.getElementById('progressbar');
	if (!canvas || canvas.getContext === undefined) {
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
	fetched = stats.fetched;
	remaining = queued - built - failed - skipped - ignored - fetched;

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
	x += minidraw(x, height, width, context, "#228B22", queued, fetched);
	x += minidraw(x, height, width, context, "#CC6633", queued, skipped);

	pctdone = ((queued - remaining) * 100) / queued;
	if (isNaN(pctdone)) {
		pctdone = 0;
	}
	if (pctdone < 1.0 && pctdone != 0) {
		pctdonetxt = "< 1";
	} else {
		pctdonetxt = Math.floor(pctdone);
	}
	$('#progresspct').text(pctdonetxt + '%');

	$('#stats_remaining').html(remaining);
}

function display_pkghour(stats, snap) {
	var attempted, pkghour, hours;

	attempted = parseInt(stats.built) + parseInt(stats.failed);
	pkghour = "--";
	if (attempted > 0 && snap.elapsed) {
		hours = snap.elapsed / 3600;
		pkghour = Math.ceil(attempted / hours);
	}
	$('#snap_pkghour').html(pkghour);
}

function display_impulse(stats, snap) {
	var attempted, pkghour, index, tail, d_pkgs, d_secs, title;

	attempted = parseInt(stats.built) + parseInt(stats.failed);
	pkghour = "--";
	index = tracker % impulse_interval;
	if (tracker < impulse_interval) {
		impulseData.push({pkgs: attempted, time: snap.elapsed});
	} else {
		impulseData[index].pkgs = attempted;
		impulseData[index].time = snap.elapsed;
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
	$('#snap .impulse').attr('title', title);
	$('#snap_impulse').html(pkghour);
}

function jail_url(mastername) {
	if (server_style == "hosted") {
		if (mastername) {
			return 'jail.html?mastername=' + encodeURIComponent(mastername);
		} else {
			return '#';
		}
	} else {
		return '../';
	}
}

function format_mastername(mastername) {
	var html;

	if (!mastername) {
		return '';
	}

	if (page_mastername && mastername == page_mastername &&
			page_type == "jail") {
		html = '<a href="#top" onclick="scrollToElement(\'#top\'); return false;">' + mastername + '</a>';
	} else {
		html = '<a title="List builds for ' + mastername + '" href="' + jail_url(mastername) + '">' +
			mastername + '</a>';
	}

	return html;
}

function format_jailname(jailname) {
	return jailname;
}

function format_setname(setname) {
	return setname;
}

function format_ptname(ptname) {
	return ptname;
}

function build_url(mastername, buildname) {
	if (!mastername || !buildname) {
		return '';
	}
	return 'build.html?' +
		'mastername=' + encodeURIComponent(mastername) + '&' +
		'build=' + encodeURIComponent(buildname);
}

function format_buildname(mastername, buildname) {
	var html;

	if (!mastername) {
		return buildname;
	} else if (!buildname) {
		return '';
	}

	if (page_mastername && mastername == page_mastername &&
		page_buildname && buildname == page_buildname &&
		page_type == "build") {
		html = '<a href="#top" onclick="scrollToElement(\'#top\'); return false;">' + buildname + '</a>';
	} else {
		html = '<a title="Show build results for ' + buildname + '" href="' + build_url(mastername, buildname) + '">' +
			buildname + '</a>';
	}

	return html;
}

function format_portset(ptname, setname) {
	return ptname + (setname ? '-' : '') + setname;
}

function format_log(pkgname, errors, text) {
	var html;

	html = '<a target="logs" title="Log for ' + pkgname + '" href="' +
		data_url + 'logs/' + (errors ? 'errors/' : '') +
		pkgname + '.log"><span class="glyphicon glyphicon-file"></span>' +
		text + '</a>';
	return html;
}

function format_start_to_end(start, end) {
	var duration;

	if (!start) {
		return '';
	}
	start = parseInt(start);
	if (isNaN(start)) {
		return '';
	}

	if (end === undefined) {
		duration = start;
	} else {
		duration = end - start;
	}

	if (duration < 0) {
		duration = 0;
	}

	return format_duration(duration);
}

function format_duration(duration) {
	var hours, minutes, seconds;

    if (duration === undefined || duration == '' || isNaN(duration)) {
      return '';
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

	scrollToElement('#skipped');
	table = $('#skipped_table').dataTable();
	table.fnFilter(pkgname, 3);

	search_filter = $('#skipped_table_filter input');
	search_filter.val(pkgname);
	search_filter.prop('disabled', true);
	search_filter.css('background-color', '#DDD');

	if (!$('#resetsearch').length) {
		search_filter.after('<span class="glyphicon glyphicon-remove ' +
				'pull-right" id="resetsearch"></span>');

		$("#resetsearch").click(function(e) {
			table.fnFilter('', 3);
			search_filter.val('');
			search_filter.prop('disabled', false);
			search_filter.css('background-color', '');
			$(this).remove();
		});
	}
}

function translate_status(status) {
	var a;

	if (status === undefined) {
		return '';
	}

	a = status.split(":");
	if (a[0] == "stopped") {
		if (a.length >= 3) {
			status = a[0] + ':' + a[1] + ':' + a[2];
		} else if (a.length >= 2) {
			status = a[0] + ':' + a[1];
		} else {
			status = a[0] + ':';
		}
	} else {
		if (a.length >= 2) {
			status = a[0] + ':' + a[1];
		} else {
			status = a[0] + ':';
		}
	}

	return status;
}

function format_skipped(skipped_cnt, pkgname) {
	if (skipped_cnt === undefined || skipped_cnt == 0) {
		return 0;
	}
	return '<a href="#skipped" onclick="filter_skipped(\'' +
		pkgname +'\'); return false;"><span class="glyphicon ' +
		'glyphicon-filter"></span>' + skipped_cnt + '</a>';
}

function format_status_row(status, row, n) {
	var table_row = [];

	table_row.push(n + 1);
	if (status == "built") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin, row.flavor));
		table_row.push(format_log(row.pkgname, false, 'success'));
		table_row.push(format_duration(row.elapsed ? row.elapsed : ''));
	} else if (status == "failed") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin, row.flavor));
		table_row.push(row.phase);
		table_row.push(row.skipped_cnt);
		table_row.push(format_log(row.pkgname, true, row.errortype));
		table_row.push(format_duration(row.elapsed ? row.elapsed : ''));
	} else if (status == "skipped") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin, row.flavor));
		table_row.push(format_pkgname(row.depends));
	} else if (status == "ignored") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin, row.flavor));
		table_row.push(row.skipped_cnt);
		table_row.push(row.reason);
	} else if (status == "fetched") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin, row.flavor));
	} else if (status == "remaining") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(row.status);
	} else if (status == "queued") {
		table_row.push(format_pkgname(row.pkgname));
		table_row.push(format_origin(row.origin, row.flavor));
		if (row.reason == "listed") {
			table_row.push(row.reason);
		} else {
			table_row.push(format_origin(row.reason));
		}
	} else {
		alert('Unknown data type "' + status + '". Try flushing cache.');
		throw 'Unknown data type "' + status + '". Try flushing cache.';
	}

	return table_row;
}

function DTRow(table_id, div_id) {
	this.Table = $('#' + table_id).DataTable();
	this.new_rows = [];
	this.first_load = (this.Table.row(0).length == 0);
	this.div_id = div_id;
}

DTRow.prototype = {
	queue: function(row) {
		var existing_row;

		/* Is this entry already in the list? If so need to
		 * replace its data. Don't bother with lookups on
		 * first load.
		 */
		row.DT_RowId = 'data_row_' + row.id;
		if (!this.first_load) {
			existing_row = this.Table.row('#' + row.DT_RowId);
		} else {
			existing_row = {};
		}
		if (existing_row.length) {
			/* Only update the row if it doesn't match the existing. */
			if (JSON.stringify(row) !==
				JSON.stringify(existing_row.data())) {
				existing_row.data(row).nodes().to$().hide().fadeIn(800);
			}
		} else {
			/* Otherwise add it. */
			this.new_rows.push(row);
		}
	},
	commit: function() {
		if (this.new_rows.length) {
			nodes = this.Table.rows.add(this.new_rows).draw().nodes();
			if (this.first_load) {
				$('#' + this.div_id).show();
			} else {
				nodes.to$().hide().fadeIn(1500);
			}
		}
	},
};

function process_data_build(data) {
	var html, a, n, table_rows, status, builder, now, row, dtrow, is_stopped;

	if (data.snap && data.snap.now) {
		// New data is relative to the 'job.started' time, not epoch.
		now = data.snap.now;
	} else {
		// Legacy data based on epoch time.
		now = Math.floor(new Date().getTime() / 1000);
	}

	// Redirect from /latest/ to the actual build.
	if (page_buildname == "latest") {
		document.location.href = build_url(page_mastername, data.buildname);
		return;
	}

	if (data.stats) {
		determine_canvas_width();
		update_canvas(data.stats);
	}

	document.title = 'Poudriere bulk results for ' + data.mastername + ' ' +
		data.buildname;

	$('#mastername').html(format_mastername(data.mastername));
	$('#buildname').html(format_buildname(data.mastername, data.buildname));
	$('#jail').html(format_jailname(data.jailname));
	$('#setname').html(format_setname(data.setname));
	$('#ptname').html(format_ptname(data.ptname));
	if (data.svn_url)
		$('#svn_url').html(data.svn_url);
	else
		$('#svn_url').hide();
	$('#build_info_div').show();

	/* Backwards compatibility */
	if (data.status && data.status instanceof Array && !data.jobs) {
		data.jobs = data.status;
		if (data.jobs[0] && data.jobs[0].id == "main") {
			data.status = data.jobs[0].status;
			data.jobs.splice(0, 1);
		} else {
			data.status = undefined;
		}
	}

	if (data.status) {
		status = translate_status(data.status);
		$('#status').text(status);
	}

	// Unknown status, assume not stopped.
	is_stopped = status ? status.match("^stopped:") : false;

	/* Builder status */
	if (data.jobs) {
		dtrow = new DTRow('builders_table', 'jobs_div');
		for (n = 0; n < data.jobs.length; n++) {
			row = {};
			builder = data.jobs[n];

			row.id = builder.id;
			row.job_id = builder.id;
			row.pkgname = builder.pkgname ? format_pkgname(builder.pkgname) : "";
			row.origin = builder.origin ? format_origin(builder.origin, builder.flavor) : "";
			row.status = builder.pkgname ?
				format_log(builder.pkgname, false, builder.status) :
				builder.status.split(":")[0];
			row.elapsed = builder.started ?
				format_start_to_end(builder.started, now) : "";

			/* Hide idle builders when the build is stopped. */
			if (!is_stopped || (row.status != "idle")) {
				dtrow.queue(row);
			}
		}
		dtrow.commit();
	}

	/* Stats */
	if (data.stats) {
		$.each(data.stats, function(status, count) {
			if (status == "elapsed") {
				count = format_start_to_end(count);
			}
			$('#stats_' + status).html(count);
		});
		$('#stats').data(data.stats);
		$('#stats').fadeIn(1400);

		if (data.snap) {
			$.each(data.snap, function(status, count) {
				if (status == "elapsed") {
					count = format_start_to_end(count);
				}
				$('#snap_' + status).html(count);
			});
			display_pkghour(data.stats, data.snap);
			display_impulse(data.stats, data.snap);
			$('#snap').fadeIn(1400);
		}
	}

	/* For each status, track how many of the existing data has been
	 * added to the table. On each update, only append new data. This
	 * is to lessen the amount of DOM redrawing on -a builds that
	 * may involve looping 24000 times. */

	if (data.ports) {
		if (data.ports["remaining"] === undefined) {
			data.ports["remaining"] = [];
		}
		$.each(data.ports, function(status, ports) {
			if (data.ports[status] &&
				(data.ports[status].length > 0 || status == "remaining")) {
				table_rows = [];
				if (status != "remaining") {
					if ((n = $('#' + status + '_body').data('index')) === undefined) {
						n = 0;
						$('#' + status + '_div').show();
						$('#nav_' + status).removeClass('disabled');
					}
					if (n == data.ports[status].length) {
						return;
					}
				} else {
					n = 0;
				}
				for (; n < data.ports[status].length; n++) {
					var row = data.ports[status][n];
					// Add in skipped counts for failures and ignores
					if (status == "failed" || status == "ignored")
						row.skipped_cnt =
							(data.skipped && data.skipped[row.pkgname]) ?
							data.skipped[row.pkgname] :
							0;

					table_rows.push(format_status_row(status, row, n));
				}
				if (status != "remaining") {
					$('#' + status + '_body').data('index', n);
					$('#' + status + '_table').DataTable().rows.add(table_rows)
						.draw(false);
				} else {
					$('#' + status + '_table').DataTable().clear().draw();
					$('#' + status + '_table').DataTable().rows.add(table_rows)
						.draw(false);
					if (table_rows.length > 0) {
						$('#' + status + '_div').show();
						$('#nav_' + status).removeClass('disabled');
					} else {
						$('#' + status + '_div').hide();
						$('#nav_' + status).addClass('disabled');
					}
				}
			}
		});
	}

	return !is_stopped;
}

function process_data_jail(data) {
	var row, build, buildname, stat, types, latest,	remaining, count, dtrow;

	if (data.builds) {
		types = ['queued', 'built', 'failed', 'skipped', 'ignored', 'fetched'];
		dtrow = new DTRow('builds_table', 'builds_div');
		for (buildname in data.builds) {
			row = {};

			build = data.builds[buildname];
			if (buildname == "latest") {
				latest = data.builds[build];
				continue;
			}

			row.id = buildname;
			row.buildname = buildname;
			for (stat in types) {
				count = build.stats && build.stats[types[stat]] !== undefined ?
					parseInt(build.stats[types[stat]]) : 0;
				row['stat_' + types[stat]] = isNaN(count) ? 0 : count;
			}
			remaining = build.stats ? (parseInt(build.stats['queued']) -
				(parseInt(build.stats['built']) +
				 parseInt(build.stats['failed']) +
				 parseInt(build.stats['skipped']) +
				 parseInt(build.stats['ignored']) +
				 parseInt(build.stats['fetched']))) : 0;
			if (isNaN(remaining)) {
				remaining = 0;
			}
			row.stat_remaining = remaining;
			row.status = translate_status(build.status);
			row.elapsed = build.elapsed ? build.elapsed : "";

			dtrow.queue(row);
		}

		if (latest) {
			$('#mastername').html(format_mastername(latest.mastername));
			$('#status').text(translate_status(latest.status));
			$('#jail').html(format_jailname(latest.jailname));
			$('#setname').html(format_setname(latest.setname));
			$('#ptname').html(format_ptname(latest.ptname));
			$('#latest_url').attr('href',
					build_url(latest.mastername, latest.buildname));
			$('#latest_build').html(format_buildname(latest.mastername,
						latest.buildname));
			$('#masterinfo_div').show();
		}

		dtrow.commit();
	}

	// Always reload, no stopping condition.
	return true;
}

function process_data_index(data) {
	var master, mastername, stat, types, latest,
		remaining, row,	count, dtrow;

	if (data.masternames) {
		types = ['queued', 'built', 'failed', 'skipped', 'ignored', 'fetched'];
		dtrow = new DTRow('latest_builds_table', 'latest_builds_div');
		for (mastername in data.masternames) {
			row = {};
			master = data.masternames[mastername].latest;

			row.id = master.mastername;
			row.portset = format_portset(master.ptname, master.setname);
			row.mastername = master.mastername;
			row.buildname = master.buildname;
			row.jailname = master.jailname;
			row.setname = master.setname;
			row.ptname = master.ptname;
			for (stat in types) {
				count = master.stats && master.stats[types[stat]] !==
					undefined ? parseInt(master.stats[types[stat]]) : 0;
				row['stat_' + types[stat]] = isNaN(count) ? 0 : count;
			}
			remaining = master.stats ? (parseInt(master.stats['queued']) -
				(parseInt(master.stats['built']) +
				 parseInt(master.stats['failed']) +
				 parseInt(master.stats['skipped']) +
				 parseInt(master.stats['ignored']) +
				 parseInt(master.stats['fetched']))) : 0;
			row.stat_remaining = isNaN(remaining) ? 0 : remaining;
			row.status = translate_status(master.status);
			row.elapsed = master.elapsed ? master.elapsed : "";

			dtrow.queue(row);
		}
		dtrow.commit();
	}

	// Always reload, no stopping condition.
	return true;
}

function process_data(data) {
	var should_reload;

	// Determine what kind of data this file actually is. Due to handling
	// file:// and inline-style setups, it may be unknown what was fetched.
	if (data.buildname) {
		// If the current page is not build.html, then redirect for the
		// sake of file:// loading.
		if (page_type != "build") {
			location.href = "build.html";
			return;
		}
		page_type = 'build';
		if (data.buildname) {
			page_buildname = data.buildname;
		}
	} else if (data.builds) {
		page_type = 'jail';
	} else if (data.masternames) {
		page_type = 'index';
	} else {
		$('#loading p').text("Invalid request. Unknown data type.")
			.addClass('error');
		return;
	}

	if (data.mastername) {
		page_mastername = data.mastername;
	}

	if (page_type == "build") {
		should_reload = process_data_build(data);
	} else if (page_type == "jail") {
		should_reload = process_data_jail(data);
	} else if (page_type == "index") {
		should_reload = process_data_index(data);
	} else {
		should_reload = false;
	}

	if (first_run) {
		/* Resize due to full content. */
		do_resize($(window));
		// Hide loading overlay
		$('#loading_overlay').fadeOut(900);
		/* Now that page is loaded, scroll to anchor. */
		if (location.hash) {
			scrollToElement(location.hash);
		}
		first_run = false;
	}

	if (should_reload) {
		setTimeout(update_data, updateInterval * 1000);
	}
}

/* Disable static navbar at the breakpoint */
function do_resize(win) {
	/* Redraw canvas to new width */
	if ($('#stats').data()) {
		determine_canvas_width();
		update_canvas($('#stats').data());
	}
	/* Resize padding for navbar/footer heights */
	$('body').css('padding-top', $('#header').outerHeight(true))
		.css('padding-bottom', $('footer').outerHeight(true));
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

function applyHovering(table_id) {
	var lastIdx, Table;

	lastIdx = null;
	Table = $('#' + table_id).DataTable();
	$('#' + table_id + ' tbody').on( 'mouseover', 'td', function () {
		var colIdx = Table.cell(this).index().column;

		if (colIdx !== lastIdx) {
			$(Table.cells().nodes()).removeClass('highlight');
			$(Table.column(colIdx).nodes()).addClass('highlight');
		}
	})
	.on('mouseleave', function () {
		$(Table.cells().nodes()).removeClass('highlight');
	});
}


function setup_build() {
	var columns, status, types, i, build_order_column, pkgname_column,
		origin_column;

	$('#builders_table').dataTable({
		"bFilter": false,
		"bInfo": false,
		"bPaginate": false,
		"bAutoWidth": false,
		"aoColumns": [
			// Smaller ID/Status
			{
				"data": "job_id",
				"sWidth": "1em",
			},
			{
				"data": "pkgname",
				"sWidth": "15em",
			},
			{
				"data": "origin",
				"sWidth": "17em",
			},
			{
				"data": "status",
				"sWidth": "10em",
			},
			{
				"data": "elapsed",
				"sWidth": "4em",
			},
		],
		"columnDefs": [
			{
				"data": null,
				"defaultContent": "",
				"targets": '_all',
			}
		],
		"stateSave": true, // Enable cookie for keeping state
		"order": [[0, 'asc']], // Sort by Job ID
	});

	build_order_column = {
		"sWidth": "1em",
		"sType": "numeric",
		"bSearchable": false,
	};

	pkgname_column = {
		"sWidth": "15em",
	};
	origin_column = {
		"sWidth": "17em",
	};

	columns = {
		"built": [
			build_order_column,
			pkgname_column,
			origin_column,
			{
				"sWidth": "4.25em",
				"bSortable": false,
				"bSearchable": false,
			},
			{
				"bSearchable": false,
				"sWidth": "3em",
			},
		],
		"failed": [
			build_order_column,
			pkgname_column,
			origin_column,
			{
				"sWidth": "6em",
			},
			{
				"sType": "numeric",
				"sWidth": "2em",
				"render": function(data, type, row) {
					return type == "display" ? format_skipped(data, row[1]) :
						data;
				},
			},
			{
				"sWidth": "7em",
			},
			{
				"bSearchable": false,
				"sWidth": "3em",
			},
		],
		"skipped": [
			build_order_column,
			pkgname_column,
			origin_column,
			pkgname_column,
		],
		"ignored": [
			build_order_column,
			pkgname_column,
			origin_column,
			{
				"sWidth": "2em",
				"sType": "numeric",
				"render": function(data, type, row) {
					return type == "display" ? format_skipped(data, row[1]) :
						data;
				},
			},
			{
				"sWidth": "25em",
			},
		],
		"fetched": [
			build_order_column,
			pkgname_column,
			origin_column,
		],
		"remaining": [
			build_order_column,
			pkgname_column,
			{
				"sWidth": "7em",
			},
		],
		"queued": [
			build_order_column,
			pkgname_column,
			origin_column,
			origin_column,
		],
	};

	types = ['built', 'failed', 'skipped', 'ignored', 'fetched', 'remaining', 'queued'];
	for (i in types) {
		status = types[i];
		$('#' + status + '_table').dataTable({
			"bAutoWidth": false,
			"processing": true, // Show processing icon
			"deferRender": true, // Defer creating TR/TD until needed
			"aoColumns": columns[status],
			"stateSave": true, // Enable cookie for keeping state
			"lengthMenu":[[5,10,25,50,100,200, -1],[5,10,25,50,100,200,"All"]],
			"pageLength": 10,
			"order": [[0, 'asc']], // Sort by build order
		});
	}
}

function setup_jail() {
	var columns, status, types, i, stat_column;

	stat_column = {
		"sWidth": "1em",
		"sType": "numeric",
		"bSearchable": false,
	};

	columns = [
		{
			"data": "buildname",
			"render": function(data, type, row) {
				return type == "display" ?
					format_buildname(page_mastername, data) :
					data;
			},
			"sWidth": "12em",
		},
		$.extend({}, stat_column, {"data": "stat_queued"}),
		$.extend({}, stat_column, {"data": "stat_built"}),
		$.extend({}, stat_column, {"data": "stat_failed"}),
		$.extend({}, stat_column, {"data": "stat_skipped"}),
		$.extend({}, stat_column, {"data": "stat_ignored"}),
		$.extend({}, stat_column, {"data": "stat_fetched"}),
		$.extend({}, stat_column, {"data": "stat_remaining"}),
		{
			"data": "status",
			"sWidth": "8em",
		},
		{
			"data": "elapsed",
			"bSearchable": false,
			"sWidth": "4em",
		},
	];

	$('#builds_table').dataTable({
		"bAutoWidth": false,
		"processing": true, // Show processing icon
		"aoColumns": columns,
		"stateSave": true, // Enable cookie for keeping state
		"lengthMenu":[[5,10,25,50,100,200, -1],[5,10,25,50,100,200,"All"]],
		"pageLength": 50,
		"columnDefs": [
			{
				"data": null,
				"defaultContent": "",
				"targets": '_all',
			}
		],
		"createdRow": function(row, data, index) {
			if (data.buildname == $('#latest_build').text()) {
				$('td.latest').removeClass('latest');
				$('td', row).addClass('latest');
			}
		},
		"order": [[0, 'asc']], // Sort by buildname
	});

	//applyHovering('builds_table');
}

function setup_index() {
	var columns, status, types, i, stat_column, table;

	stat_column = {
		"sWidth": "1em",
		"sType": "numeric",
		"bSearchable": false,
	};

	columns = [
		{
			"data": "portset",
			"visible": false,
		},
		{
			"data": "mastername",
			"render": function(data, type, row) {
				return type == "display" ? format_mastername(data) :
					data;
			},
			"sWidth": "22em",
		},
		{
			"data": "buildname",
			"render": function(data, type, row) {
				return type == "display" ?
					format_buildname(row.mastername, data) : data;
			},
			"sWidth": "12em",
		},
		{
			"data": "jailname",
			"render": function(data, type, row) {
				return type == "display" ? format_jailname(data) : data;
			},
			"sWidth": "10em",
			"visible": false,
		},
		{
			"data": "setname",
			"render": function(data, type, row) {
				return type == "display" ? format_setname(data) : data;
			},
			"sWidth": "10em",
			"visible": false,
		},
		{
			"data": "ptname",
			"render": function(data, type, row) {
				return type == "display" ? format_ptname(data) : data;
			},
			"sWidth": "10em",
			"visible": false,
		},
		$.extend({}, stat_column, {"data": "stat_queued"}),
		$.extend({}, stat_column, {"data": "stat_built"}),
		$.extend({}, stat_column, {"data": "stat_failed"}),
		$.extend({}, stat_column, {"data": "stat_skipped"}),
		$.extend({}, stat_column, {"data": "stat_ignored"}),
		$.extend({}, stat_column, {"data": "stat_fetched"}),
		$.extend({}, stat_column, {"data": "stat_remaining"}),
		{
			"data": "status",
			"sWidth": "8em",
		},
		{
			"data": "elapsed",
			"bSearchable": false,
			"sWidth": "4em",
		},
	];

	table = $('#latest_builds_table').dataTable({
		"bAutoWidth": false,
		"processing": true, // Show processing icon
		"aoColumns": columns,
		"stateSave": true, // Enable cookie for keeping state
		"lengthMenu":[[5,10,25,50,100,200, -1],[5,10,25,50,100,200,"All"]],
		"pageLength": 50,
		"order": [[2, 'asc']], // Sort by buildname
		"columnDefs": [
			{
				"data": null,
				"defaultContent": "",
				"targets": '_all',
			}
		],
	});

	table.rowGrouping({
		iGroupingColumnIndex2: 4,
		iGroupingColumnIndex: 5,
		sGroupLabelPrefix2: "&nbsp;&nbsp;Set - ",
		sGroupLabelPrefix: "Ports - ",
		sEmptyGroupLabel: "",
		fnGroupLabelFormat: function(label) {
			return "<span class='title'>"+ label + "</span>";
		},
		fnGroupLabelFormat2: function(label) {
			return "<span class='title'>"+ label + "</span>";
		},
		fnOnGrouped: function() {
			// Hide default set group rows
			$('#latest_builds_table tbody tr[id^=group-id-latest_builds_table_][id$=--]').hide();
		},
	});

	//applyHovering('latest_builds_table');
}

$(document).ready(function() {
	var pathname;

	pathname = location.pathname.substring(location.pathname.lastIndexOf("/") + 1);
	if (pathname == "") {
		page_type = "index";
	} else {
		page_type = pathname.substr(0, pathname.length - 5);
	}

	if (page_type == "build") {
		if (server_style == "hosted") {
			page_mastername = getParameterByName("mastername");
			page_buildname = getParameterByName("build");
			if (!page_mastername || !page_buildname) {
				$('#loading p').text('Invalid request. Mastername and Build required.').addClass('error');
				return;
			}
			data_url = 'data/' + page_mastername + '/' +
			    page_buildname + '/';
			$('a.data_url').each(function() {
				var href = $(this).attr('href');
				$(this).attr('href', data_url + href);
			});
			$('#master_link').attr('href', jail_url(page_mastername));
		} else if (server_style == "inline") {
			$('#master_link').attr('href', '../');
			$('#index_link').attr('href', '../../');
		}
		setup_build();
	} else if (page_type == "jail") {
		if (server_style == "hosted") {
			page_mastername = getParameterByName("mastername");
			if (!page_mastername) {
				$('#loading p').text('Invalid request. Mastername required.').addClass('error');
				return;
			}
			data_url = 'data/' + page_mastername + '/';
			$('a.data_url').each(function() {
				var href = $(this).attr('href');
				$(this).attr('href', data_url + href);
			});
			$('#latest_url').attr('href', build_url(page_mastername, 'latest'));
		} else if (server_style == "inline") {
			$('#index_link').attr('href', '../');
		}
		setup_jail();
	} else if (page_type == "index") {
		if (server_style == "hosted") {
			data_url = 'data/';
			$('a.data_url').each(function() {
				var href = $(this).attr('href');
				$(this).attr('href', data_url + href);
			});
		}
		setup_index();
	} else {
		$('#loading p').text("Invalid request. Unhandled page type '" +
				page_type + "'").addClass('error');
		return;
	}

	/* Activate tooltip hovers */
	$('[data-toggle="tooltip"]').tooltip();

	/* Fix nav links to not skip hashchange event when clicking multiple
	 * times. */
	$("#header .nav a[href^=#]").each(function(){
		var href = $(this).attr('href');
		if (href != '#') {
			$(this).click(function(e) {
				e.preventDefault();
				if (location.hash != href) {
					location.hash = href;
				}
				scrollToElement(href);
			});
		}
	})
	/* Force minimum width on mobile, will zoom to fit. */
	$(window).bind('orientationchange', function(e) {fix_viewport();});
	fix_viewport();
	/* Handle resize needs */
	$(window).on('resize', function() {do_resize($(this));});
	do_resize($(window));

	update_data();
});

$(document).bind("keydown", function(e) {
	/* Disable F5 refreshing since this is AJAX driven. */
	if (e.which == 116) {
		e.preventDefault();
	}
});
