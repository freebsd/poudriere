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
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS "AS IS" AND
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

// server_style = ['hosted', 'inline'];
const serverStyle = 'hosted';

const updateInterval = 8;
let firstRun = true;
let loadAttempts = 0;
const maxLoadAttempts = 8;
const firstLoadInterval = 2;
let canvasWidth;
const impulseData = [];
let tracker = 0;
const impulseFirstPeriod = 120;
const impulseTargetPeriod = 600;
const impulseFirstInterval = impulseFirstPeriod / updateInterval;
const impulseInterval = impulseTargetPeriod / updateInterval;
let pageType;
let pageBuildName;
let pageMasterName;
let dataURL = '';

function getParameterByName(name) {
  name = name.replace(/[[]/, '\\[').replace(/[\]]/, '\\]');
  const regex = new RegExp(`[\\?&]${name}=([^&#]*)`);
  const results = regex.exec(window.location.search);
  return results == null
    ? ''
    : decodeURIComponent(results[1].replace(/\+/g, ' '));
}

function scrollOffset() {
  return -1 * parseFloat($('body').css('padding-top'));
}

function scrollToElement(element) {
  const ele = $(element);
  if (!ele.length) {
    return;
  }
  $('body,html,document').scrollTop(ele.offset().top + scrollOffset());
}

function formatOrigin(origin, flavor) {
  if (!origin) {
    return '';
  }

  const data = origin.split('/');

  if (flavor) {
    flavor = `@${flavor}`;
  } else {
    flavor = '';
  }

  return (
    `<a target="_new" title="freshports for ${
      origin
    }" href="https://www.freshports.org/${
      data[0]
    }/${
      data[1]
    }/"><span `
    + `class="glyphicon glyphicon-tasks"></span>${
      origin
    }${flavor
    }</a>`
  );
}

function formatPkgName(pkgname) {
  return pkgname;
}

function determineCanvasWidth() {
  let width;

  /* Determine width by how much space the column has, minus the size of
   * displaying the percentage at 100%
   */
  width = $('#progress_col').width();
  $('#progresspct').text('100%');
  width = width - $('#progresspct').width() - 20;
  $('#progresspct').text('');
  canvasWidth = width;
}

function updateCanvas(stats) {
  let pctdone;
  let height; let width;
  let pctdonetxt;

  if (stats.queued === undefined) {
    return;
  }

  const canvas = document.getElementById('progressbar');
  if (!canvas || canvas.getContext === undefined) {
    /* Not supported */
    return;
  }

  height = 10;
  width = canvasWidth;

  canvas.height = height;
  canvas.width = width;

  const { queued } = stats;
  const { built } = stats;
  const { failed } = stats;
  const { skipped } = stats;
  const { ignored } = stats;
  const { fetched } = stats;
  const remaining = queued - built - failed - skipped - ignored - fetched;

  const context = canvas.getContext('2d');

  context.beginPath();
  context.rect(0, 0, width, height);
  /* Save 2 pixels for border */
  height -= 2;
  /* Start at 1 and save 1 for border */
  width -= 1;
  context.fillStyle = '#E3E3E3';
  context.fillRect(1, 1, width, height);
  context.lineWidth = 1;
  context.strokeStyle = 'black';
  context.stroke();

  pctdone = ((queued - remaining) * 100) / queued;
  if (Number.isNaN(pctdone)) {
    pctdone = 0;
  }
  if (pctdone < 1.0 && pctdone !== 0) {
    pctdonetxt = '< 1';
  } else {
    pctdonetxt = Math.floor(pctdone);
  }
  $('#progresspct').text(`${pctdonetxt}%`);

  $('#stats_remaining').html(remaining);
}

function displayPkgHour(stats, snap) {
  let pkghour;
  let hours;

  const attempted = parseInt(stats.built, 10) + parseInt(stats.failed, 10);
  pkghour = '--';
  if (attempted > 0 && snap.elapsed) {
    hours = snap.elapsed / 3600;
    pkghour = Math.ceil(attempted / hours);
  }
  $('#snap_pkghour').html(pkghour);
}

function displayImpulse(stats, snap) {
  let pkghour; let tail; let dPkgs; let dSecs; let title;

  const attempted = parseInt(stats.built, 10) + parseInt(stats.failed, 10);
  pkghour = '--';
  const index = tracker % impulseInterval;
  if (tracker < impulseInterval) {
    impulseData.push({ pkgs: attempted, time: snap.elapsed });
  } else {
    impulseData[index].pkgs = attempted;
    impulseData[index].time = snap.elapsed;
  }
  if (tracker >= impulseFirstInterval) {
    if (tracker < impulseInterval) {
      tail = 0;
      title = `Package build rate over last ${
        Math.floor((tracker * updateInterval) / 60)
      } minutes`;
    } else {
      tail = (tracker - (impulseInterval - 1)) % impulseInterval;
      title = `Package build rate over last ${
        impulseTargetPeriod / 60
      } minutes`;
    }
    dPkgs = impulseData[index].pkgs - impulseData[tail].pkgs;
    dSecs = impulseData[index].time - impulseData[tail].time;
    pkghour = Math.ceil(dPkgs / (dSecs / 3600));
  } else {
    title = 'Package build rate. Still calculating...';
  }
  tracker += 1;
  $('#snap .impulse').attr('title', title);
  $('#snap_impulse').html(pkghour);
}

function jailURL(mastername) {
  if (serverStyle === 'hosted') {
    if (mastername) {
      return `jail.html?mastername=${encodeURIComponent(mastername)}`;
    }
    return '#';
  }
  return '../';
}

function formatMasterName(mastername) {
  let html;

  if (!mastername) {
    return '';
  }

  if (pageMasterName && mastername === pageMasterName && pageType === 'jail') {
    html = `<a href="#top" onclick="scrollToElement('#top'); return false;">${
      mastername
    }</a>`;
  } else {
    html = `<a title="List builds for ${
      mastername
    }" href="${
      jailURL(mastername)
    }">${
      mastername
    }</a>`;
  }

  return html;
}

function formatJailName(jailname) {
  return jailname;
}

function formatSetName(setname) {
  return setname;
}

function formatPtName(ptname) {
  return ptname;
}

function buildURL(mastername, buildname) {
  if (!mastername || !buildname) {
    return '';
  }
  return (
    'build.html?'
    + `mastername=${
      encodeURIComponent(mastername)
    }&`
    + `build=${
      encodeURIComponent(buildname)}`
  );
}

function formatBuildName(mastername, buildname) {
  let html;

  if (!mastername) {
    return buildname;
  } if (!buildname) {
    return '';
  }

  if (
    pageMasterName
    && mastername === pageMasterName
    && pageBuildName
    && buildname === pageBuildName
    && pageType === 'build'
  ) {
    html = `<a href="#top" onclick="scrollToElement('#top'); return false;">${
      buildname
    }</a>`;
  } else {
    html = `<a title="Show build results for ${
      buildname
    }" href="${
      buildURL(mastername, buildname)
    }">${
      buildname
    }</a>`;
  }

  return html;
}

function formatPortSet(ptname, setname) {
  return ptname + (setname ? '-' : '') + setname;
}

function formatLog(pkgname, errors, text) {
  const html = `<a target="logs" title="Log for ${
    pkgname
  }" href="${
    dataURL
  }logs/${
    errors ? 'errors/' : ''
  }${pkgname
  }.log"><span class="glyphicon glyphicon-file"></span>${
    text
  }</a>`;
  return html;
}

function format_duration(duration) {
  let hours; let minutes; let
    seconds;

  if (duration === undefined || duration === '' || Number.isNaN(duration)) {
    return '';
  }

  hours = Math.floor(duration / 3600);
  duration -= hours * 3600;
  minutes = Math.floor(duration / 60);
  seconds = duration - minutes * 60;

  if (hours < 10) {
    hours = `0${hours}`;
  }
  if (minutes < 10) {
    minutes = `0${minutes}`;
  }
  if (seconds < 10) {
    seconds = `0${seconds}`;
  }

  return `${hours}:${minutes}:${seconds}`;
}

function format_start_to_end(start, end) {
  let duration;

  if (!start) {
    return '';
  }
  start = parseInt(start, 10);
  if (Number.isNaN(start)) {
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

function filter_skipped(pkgname) {
  scrollToElement('#skipped');
  const table = $('#skipped_table').dataTable();
  table.fnFilter(pkgname, 3);

  const search_filter = $('#skipped_table_filter input');
  search_filter.val(pkgname);
  search_filter.prop('disabled', true);
  search_filter.css('background-color', '#DDD');

  if (!$('#resetsearch').length) {
    search_filter.after(
      '<span class="glyphicon glyphicon-remove '
        + 'pull-right" id="resetsearch"></span>',
    );

    $('#resetsearch').click(() => {
      table.fnFilter('', 3);
      search_filter.val('');
      search_filter.prop('disabled', false);
      search_filter.css('background-color', '');
      $(this).remove();
    });
  }
}

function translate_status(status) {
  if (status === undefined) {
    return '';
  }

  const a = status.split(':');
  if (a[0] === 'stopped') {
    if (a.length >= 3) {
      status = `${a[0]}:${a[1]}:${a[2]}`;
    } else if (a.length >= 2) {
      status = `${a[0]}:${a[1]}`;
    } else {
      status = `${a[0]}:`;
    }
  } else if (a.length >= 2) {
    status = `${a[0]}:${a[1]}`;
  } else {
    status = `${a[0]}:`;
  }

  return status;
}

function format_skipped(skipped_cnt, pkgname) {
  if (skipped_cnt === undefined || skipped_cnt === 0) {
    return 0;
  }
  return (
    `<a href="#skipped" onclick="filter_skipped('${
      pkgname
    }'); return false;"><span class="glyphicon `
    + `glyphicon-filter"></span>${
      skipped_cnt
    }</a>`
  );
}

function format_status_row(status, row, n) {
  const table_row = [];

  table_row.push(n + 1);
  if (status === 'built') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(formatOrigin(row.origin, row.flavor));
    table_row.push(formatLog(row.pkgname, false, 'success'));
    table_row.push(format_duration(row.elapsed ? row.elapsed : ''));
  } else if (status === 'failed') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(formatOrigin(row.origin, row.flavor));
    table_row.push(row.phase);
    table_row.push(row.skipped_cnt);
    table_row.push(formatLog(row.pkgname, true, row.errortype));
    table_row.push(format_duration(row.elapsed ? row.elapsed : ''));
  } else if (status === 'skipped') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(formatOrigin(row.origin, row.flavor));
    table_row.push(formatPkgName(row.depends));
  } else if (status === 'ignored') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(formatOrigin(row.origin, row.flavor));
    table_row.push(row.skipped_cnt);
    table_row.push(row.reason);
  } else if (status === 'fetched') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(formatOrigin(row.origin, row.flavor));
  } else if (status === 'remaining') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(row.status);
  } else if (status === 'queued') {
    table_row.push(formatPkgName(row.pkgname));
    table_row.push(formatOrigin(row.origin, row.flavor));
    if (row.reason === 'listed') {
      table_row.push(row.reason);
    } else {
      table_row.push(formatOrigin(row.reason));
    }
  } else {
    throw new Error(`Unknown data type "${status}". Try flushing cache.`);
  }

  return table_row;
}

function DTRow(table_id, div_id) {
  this.Table = $(`#${table_id}`).DataTable();
  this.new_rows = [];
  this.first_load = this.Table.row(0).length === 0;
  this.div_id = div_id;
}

DTRow.prototype = {
  queue(row) {
    let existing_row;

    /* Is this entry already in the list? If so need to
     * replace its data. Don't bother with lookups on
     * first load.
     */
    row.DT_RowId = `data_row_${row.id}`;
    if (!this.first_load) {
      existing_row = this.Table.row(`#${row.DT_RowId}`);
    } else {
      existing_row = {};
    }
    if (existing_row.length) {
      /* Only update the row if it doesn't match the existing. */
      if (JSON.stringify(row) !== JSON.stringify(existing_row.data())) {
        existing_row.data(row).nodes().to$().hide()
          .fadeIn(800);
      }
    } else {
      /* Otherwise add it. */
      this.new_rows.push(row);
    }
  },
  commit() {
    if (this.new_rows.length) {
      const nodes = this.Table.rows.add(this.new_rows).draw().nodes();
      if (this.first_load) {
        $(`#${this.div_id}`).show();
      } else {
        nodes.to$().hide().fadeIn(1500);
      }
    }
  },
};

function process_data_build(data) {
  let n; let table_rows; let status; let builder; let now; let row; let dtrow;

  if (data.snap && data.snap.now) {
    // New data is relative to the 'job.started' time, not epoch.
    now = data.snap.now;
  } else {
    // Legacy data based on epoch time.
    now = Math.floor(new Date().getTime() / 1000);
  }

  // Redirect from /latest/ to the actual build.
  if (pageBuildName === 'latest') {
    window.location.href = buildURL(pageMasterName, data.buildname);
    return undefined;
  }

  if (data.stats) {
    determineCanvasWidth();
    updateCanvas(data.stats);
  }

  document.title = `Poudriere bulk results for ${data.mastername} ${data.buildname}`;

  $('#mastername').html(formatMasterName(data.mastername));
  $('#buildname').html(formatBuildName(data.mastername, data.buildname));
  $('#jail').html(formatJailName(data.jailname));
  $('#setname').html(formatSetName(data.setname));
  $('#ptname').html(formatPtName(data.ptname));
  if (data.overlays) {
    $('#overlays').html(data.overlays);
  } else {
    $('#overlays').hide();
    $('#overlays_title').hide();
  }
  if (data.git_hash) {
    $('#git_hash').html(data.git_hash + (data.git_dirty === 'yes' ? ' (dirty)' : ''));
  } else {
    $('#git_hash').hide();
    $('#git_hash_title').hide();
  }
  $('#build_info_div').show();

  /* Backwards compatibility */
  if (data.status && data.status instanceof Array && !data.jobs) {
    data.jobs = data.status;
    if (data.jobs[0] && data.jobs[0].id === 'main') {
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
  const is_stopped = status ? status.match('^stopped:') : false;

  /* Builder status */
  if (data.jobs) {
    dtrow = new DTRow('builders_table', 'jobs_div');
    for (n = 0; n < data.jobs.length; n += 1) {
      row = {};
      builder = data.jobs[n];

      row.id = builder.id;
      row.job_id = builder.id;
      row.pkgname = builder.pkgname ? formatPkgName(builder.pkgname) : '';
      row.origin = builder.origin
        ? formatOrigin(builder.origin, builder.flavor)
        : '';
      row.status = builder.pkgname
        ? formatLog(builder.pkgname, false, builder.status)
        : builder.status.split(':')[0];
      row.elapsed = builder.started
        ? format_start_to_end(builder.started, now)
        : '';

      /* Hide idle builders when the build is stopped. */
      if (!is_stopped || row.status !== 'idle') {
        dtrow.queue(row);
      }
    }
    dtrow.commit();
  }

  /* Stats */
  if (data.stats) {
    $.each(data.stats, (stat, count) => {
      if (stat === 'elapsed') {
        count = format_start_to_end(count);
      }
      $(`#stats_${stat}`).html(count);
    });
    $('#stats').data(data.stats);
    $('#stats').fadeIn(1400);

    if (data.snap) {
      $.each(data.snap, (stat, count) => {
        if (stat === 'elapsed') {
          count = format_start_to_end(count);
        }
        $(`#snap_${stat}`).html(count);
      });
      displayPkgHour(data.stats, data.snap);
      displayImpulse(data.stats, data.snap);
      $('#snap').fadeIn(1400);
    }
  }

  /* For each status, track how many of the existing data has been
   * added to the table. On each update, only append new data. This
   * is to lessen the amount of DOM redrawing on -a builds that
   * may involve looping 24000 times. */

  if (data.ports) {
    if (data.ports.remaining === undefined) {
      data.ports.remaining = [];
    }
    $.each(data.ports, (stat) => {
      if (stat === 'tobuild') {
        return;
      }
      if (
        data.ports[stat]
        && (data.ports[stat].length > 0 || stat === 'remaining')
      ) {
        table_rows = [];
        if (stat !== 'remaining') {
          n = $(`#${stat}_body`).data('index');
          if (n === undefined) {
            n = 0;
            $(`#${stat}_div`).show();
            $(`#nav_${stat}`).removeClass('disabled');
          }
          if (n === data.ports[stat].length) {
            return;
          }
        } else {
          n = 0;
        }
        for (; n < data.ports[stat].length; n += 1) {
          const fetchedRow = data.ports[stat][n];
          // Add in skipped counts for failures and ignores
          if (stat === 'failed' || stat === 'ignored') {
            fetchedRow.skipped_cnt = data.skipped && data.skipped[fetchedRow.pkgname]
              ? data.skipped[fetchedRow.pkgname]
              : 0;
          }

          table_rows.push(format_status_row(stat, fetchedRow, n));
        }
        if (stat !== 'remaining') {
          $(`#${stat}_body`).data('index', n);
          $(`#${stat}_table`)
            .DataTable()
            .rows.add(table_rows)
            .draw(false);
        } else {
          $(`#${stat}_table`)
            .DataTable()
            .clear()
            .draw();
          $(`#${stat}_table`)
            .DataTable()
            .rows.add(table_rows)
            .draw(false);
          if (table_rows.length > 0) {
            $(`#${stat}_div`).show();
            $(`#nav_${stat}`).removeClass('disabled');
          } else {
            $(`#${stat}_div`).hide();
            $(`#nav_${stat}`).addClass('disabled');
          }
        }
      }
    });
  }

  return !is_stopped;
}

function process_data_jail(data) {
  let row; let build; let buildname; let stat; let types; let latest; let remaining; let count; let
    dtrow;

  if (data.builds) {
    types = ['queued', 'built', 'failed', 'skipped', 'ignored', 'fetched'];
    dtrow = new DTRow('builds_table', 'builds_div');
    for (buildname in data.builds) {
      if (buildname !== undefined) {
        row = {};

        build = data.builds[buildname];
        if (buildname === 'latest') {
          latest = data.builds[build];
          continue;
        }

        row.id = buildname;
        row.buildname = buildname;
        for (stat in types) {
          if (stat !== undefined) {
            count = build.stats && build.stats[types[stat]] !== undefined
              ? parseInt(build.stats[types[stat]], 10)
              : 0;
            row[`stat_${types[stat]}`] = Number.isNaN(count) ? 0 : count;
          }
        }
        remaining = build.stats
          ? parseInt(build.stats.queued, 10)
          - (parseInt(build.stats.built, 10)
            + parseInt(build.stats.failed, 10)
            + parseInt(build.stats.skipped, 10)
            + parseInt(build.stats.ignored, 10)
            + parseInt(build.stats.fetched, 10))
          : 0;
        if (Number.isNaN(remaining)) {
          remaining = 0;
        }
        row.stat_remaining = remaining;
        row.status = translate_status(build.status);
        row.elapsed = build.elapsed ? build.elapsed : '';

        dtrow.queue(row);
      }
    }

    if (latest) {
      $('#mastername').html(formatMasterName(latest.mastername));
      $('#status').text(translate_status(latest.status));
      $('#jail').html(formatJailName(latest.jailname));
      $('#setname').html(formatSetName(latest.setname));
      $('#ptname').html(formatPtName(latest.ptname));
      $('#latest_url').attr(
        'href',
        buildURL(latest.mastername, latest.buildname),
      );
      $('#latest_build').html(
        formatBuildName(latest.mastername, latest.buildname),
      );
      $('#masterinfo_div').show();
    }

    dtrow.commit();
  }

  // Always reload, no stopping condition.
  return true;
}

function process_data_index(data) {
  let master; let mastername; let stat; let types; let remaining;
  let row; let count; let dtrow;

  if (data.masternames) {
    types = ['queued', 'built', 'failed', 'skipped', 'ignored', 'fetched'];
    dtrow = new DTRow('latest_builds_table', 'latest_builds_div');
    for (mastername in data.masternames) {
      if (mastername !== undefined) {
        row = {};
        master = data.masternames[mastername].latest;

        row.id = master.mastername;
        row.portset = formatPortSet(master.ptname, master.setname);
        row.mastername = master.mastername;
        row.buildname = master.buildname;
        row.jailname = master.jailname;
        row.setname = master.setname;
        row.ptname = master.ptname;
        for (stat in types) {
          if (stat !== undefined) {
            count = master.stats && master.stats[types[stat]] !== undefined
              ? parseInt(master.stats[types[stat]], 10)
              : 0;
            row[`stat_${types[stat]}`] = Number.isNaN(count) ? 0 : count;
          }
        }
        remaining = master.stats
          ? parseInt(master.stats.queued, 10)
          - (parseInt(master.stats.built, 10)
            + parseInt(master.stats.failed, 10)
            + parseInt(master.stats.skipped, 10)
            + parseInt(master.stats.ignored, 10)
            + parseInt(master.stats.fetched, 10))
          : 0;
        row.stat_remaining = Number.isNaN(remaining) ? 0 : remaining;
        row.status = translate_status(master.status);
        row.elapsed = master.elapsed ? master.elapsed : '';

        dtrow.queue(row);
      }
    }
    dtrow.commit();
  }

  // Always reload, no stopping condition.
  return true;
}

/* Disable static navbar at the breakpoint */
function do_resize() {
  /* Redraw canvas to new width */
  if ($('#stats').data()) {
    determineCanvasWidth();
    updateCanvas($('#stats').data());
  }
  /* Resize padding for navbar/footer heights */
  $('body')
    .css('padding-top', $('#header').outerHeight(true))
    .css('padding-bottom', $('footer').outerHeight(true));
}

function process_data(data) {
  let should_reload;

  // Determine what kind of data this file actually is. Due to handling
  // file:// and inline-style setups, it may be unknown what was fetched.
  if (data.buildname) {
    // If the current page is not build.html, then redirect for the
    // sake of file:// loading.
    if (pageType !== 'build') {
      window.location.href = 'build.html';
      return;
    }
    pageType = 'build';
    if (data.buildname) {
      pageBuildName = data.buildname;
    }
  } else if (data.builds) {
    pageType = 'jail';
  } else if (data.masternames) {
    pageType = 'index';
  } else {
    $('#loading p')
      .text('Invalid request. Unknown data type.')
      .addClass('error');
    return;
  }

  if (data.mastername) {
    pageMasterName = data.mastername;
  }

  if (pageType === 'build') {
    should_reload = process_data_build(data);
  } else if (pageType === 'jail') {
    should_reload = process_data_jail(data);
  } else if (pageType === 'index') {
    should_reload = process_data_index(data);
  } else {
    should_reload = false;
  }

  if (firstRun) {
    /* Resize due to full content. */
    do_resize($(window));
    // Hide loading overlay
    $('#loading_overlay').fadeOut(900);
    /* Now that page is loaded, scroll to anchor. */
    if (window.location.hash) {
      scrollToElement(window.location.hash);
    }
    firstRun = false;
  }

  if (should_reload) {
    setTimeout(update_data, updateInterval * 1000);
  }
}

function update_data() {
  $.ajax({
    url: `${dataURL}.data.json`,
    dataType: 'json',
    headers: {
      'Cache-Control': 'max-age=0',
    },
    success(data) {
      loadAttempts = 0;
      process_data(data);
    },
    error() {
      loadAttempts += 1;
      if (loadAttempts < maxLoadAttempts) {
        /* May not be there yet, try again shortly */
        setTimeout(update_data, firstLoadInterval * 1000);
      } else {
        $('#loading p')
          .text('Invalid request or no data available yet.')
          .addClass('error');
      }
    },
  });
}

/* Force minimum width on mobile, will zoom to fit. */
function fix_viewport() {
  const minimum_width = parseInt($('body').css('min-width'), 10);
  if (minimum_width !== 0 && window.innerWidth < minimum_width) {
    $('meta[name=viewport]').attr('content', `width=${minimum_width}`);
  } else {
    $('meta[name=viewport]').attr(
      'content',
      'width=device-width, initial-scale=1.0',
    );
  }
}

function setup_build() {
  let status;
  let i;

  $('#builders_table').dataTable({
    bFilter: false,
    bInfo: false,
    bPaginate: false,
    bAutoWidth: false,
    aoColumns: [
      // Smaller ID/Status
      {
        data: 'job_id',
        sWidth: '1em',
      },
      {
        data: 'pkgname',
        sWidth: '15em',
      },
      {
        data: 'origin',
        sWidth: '17em',
      },
      {
        data: 'status',
        sWidth: '10em',
      },
      {
        data: 'elapsed',
        sWidth: '4em',
      },
    ],
    columnDefs: [
      {
        data: null,
        defaultContent: '',
        targets: '_all',
      },
    ],
    stateSave: true, // Enable cookie for keeping state
    order: [[0, 'asc']], // Sort by Job ID
  });

  const build_order_column = {
    sWidth: '1em',
    sType: 'numeric',
    bSearchable: false,
  };

  const pkgname_column = {
    sWidth: '15em',
  };
  const origin_column = {
    sWidth: '17em',
  };

  const columns = {
    built: [
      build_order_column,
      pkgname_column,
      origin_column,
      {
        sWidth: '4.25em',
        bSortable: false,
        bSearchable: false,
      },
      {
        bSearchable: false,
        sWidth: '3em',
      },
    ],
    failed: [
      build_order_column,
      pkgname_column,
      origin_column,
      {
        sWidth: '6em',
      },
      {
        sType: 'numeric',
        sWidth: '2em',
        render(data, type, row) {
          return type === 'display' ? format_skipped(data, row[1]) : data;
        },
      },
      {
        sWidth: '7em',
      },
      {
        bSearchable: false,
        sWidth: '3em',
      },
    ],
    skipped: [
      build_order_column,
      pkgname_column,
      origin_column,
      pkgname_column,
    ],
    ignored: [
      build_order_column,
      pkgname_column,
      origin_column,
      {
        sWidth: '2em',
        sType: 'numeric',
        render(data, type, row) {
          return type === 'display' ? format_skipped(data, row[1]) : data;
        },
      },
      {
        sWidth: '25em',
      },
    ],
    fetched: [build_order_column, pkgname_column, origin_column],
    remaining: [
      build_order_column,
      pkgname_column,
      {
        sWidth: '7em',
      },
    ],
    queued: [build_order_column, pkgname_column, origin_column, origin_column],
  };

  const types = [
    'built',
    'failed',
    'skipped',
    'ignored',
    'fetched',
    'remaining',
    'queued',
  ];
  for (i in types) {
    if (i !== undefined) {
      status = types[i];
      $(`#${status}_table`).dataTable({
        bAutoWidth: false,
        processing: true, // Show processing icon
        deferRender: true, // Defer creating TR/TD until needed
        aoColumns: columns[status],
        stateSave: true, // Enable cookie for keeping state
        lengthMenu: [
          [5, 10, 25, 50, 100, 200, -1],
          [5, 10, 25, 50, 100, 200, 'All'],
        ],
        pageLength: 10,
        order: [[0, 'asc']], // Sort by build order
      });
    }
  }
}

function setup_jail() {
  const stat_column = {
    sWidth: '1em',
    sType: 'numeric',
    bSearchable: false,
  };

  const columns = [
    {
      data: 'buildname',
      render(data, type) {
        return type === 'display'
          ? formatBuildName(pageMasterName, data)
          : data;
      },
      sWidth: '12em',
    },
    $.extend({}, stat_column, { data: 'stat_queued' }),
    $.extend({}, stat_column, { data: 'stat_built' }),
    $.extend({}, stat_column, { data: 'stat_failed' }),
    $.extend({}, stat_column, { data: 'stat_skipped' }),
    $.extend({}, stat_column, { data: 'stat_ignored' }),
    $.extend({}, stat_column, { data: 'stat_fetched' }),
    $.extend({}, stat_column, { data: 'stat_remaining' }),
    {
      data: 'status',
      sWidth: '8em',
    },
    {
      data: 'elapsed',
      bSearchable: false,
      sWidth: '4em',
    },
  ];

  $('#builds_table').dataTable({
    bAutoWidth: false,
    processing: true, // Show processing icon
    aoColumns: columns,
    stateSave: true, // Enable cookie for keeping state
    lengthMenu: [
      [5, 10, 25, 50, 100, 200, -1],
      [5, 10, 25, 50, 100, 200, 'All'],
    ],
    pageLength: 50,
    columnDefs: [
      {
        data: null,
        defaultContent: '',
        targets: '_all',
      },
    ],
    createdRow(row, data) {
      if (data.buildname === $('#latest_build').text()) {
        $('td.latest').removeClass('latest');
        $('td', row).addClass('latest');
      }
    },
    order: [[0, 'asc']], // Sort by buildname
  });
}

function setup_index() {
  const stat_column = {
    sWidth: '1em',
    sType: 'numeric',
    bSearchable: false,
  };

  const columns = [
    {
      data: 'portset',
      visible: false,
    },
    {
      data: 'mastername',
      render(data, type) {
        return type === 'display' ? formatMasterName(data) : data;
      },
      sWidth: '22em',
    },
    {
      data: 'buildname',
      render(data, type, row) {
        return type === 'display'
          ? formatBuildName(row.mastername, data)
          : data;
      },
      sWidth: '12em',
    },
    {
      data: 'jailname',
      render(data, type) {
        return type === 'display' ? formatJailName(data) : data;
      },
      sWidth: '10em',
      visible: false,
    },
    {
      data: 'setname',
      render(data, type) {
        return type === 'display' ? formatSetName(data) : data;
      },
      sWidth: '10em',
      visible: false,
    },
    {
      data: 'ptname',
      render(data, type) {
        return type === 'display' ? formatPtName(data) : data;
      },
      sWidth: '10em',
      visible: false,
    },
    $.extend({}, stat_column, { data: 'stat_queued' }),
    $.extend({}, stat_column, { data: 'stat_built' }),
    $.extend({}, stat_column, { data: 'stat_failed' }),
    $.extend({}, stat_column, { data: 'stat_skipped' }),
    $.extend({}, stat_column, { data: 'stat_ignored' }),
    $.extend({}, stat_column, { data: 'stat_fetched' }),
    $.extend({}, stat_column, { data: 'stat_remaining' }),
    {
      data: 'status',
      sWidth: '8em',
    },
    {
      data: 'elapsed',
      bSearchable: false,
      sWidth: '4em',
    },
  ];

  const table = $('#latest_builds_table').dataTable({
    bAutoWidth: false,
    processing: true, // Show processing icon
    aoColumns: columns,
    stateSave: true, // Enable cookie for keeping state
    lengthMenu: [
      [5, 10, 25, 50, 100, 200, -1],
      [5, 10, 25, 50, 100, 200, 'All'],
    ],
    pageLength: 50,
    order: [[2, 'asc']], // Sort by buildname
    columnDefs: [
      {
        data: null,
        defaultContent: '',
        targets: '_all',
      },
    ],
  });

  table.rowGrouping({
    iGroupingColumnIndex2: 4,
    iGroupingColumnIndex: 5,
    sGroupLabelPrefix2: '&nbsp;&nbsp;Set - ',
    sGroupLabelPrefix: 'Ports - ',
    sEmptyGroupLabel: '',
    fnGroupLabelFormat(label) {
      return `<span class='title'>${label}</span>`;
    },
    fnGroupLabelFormat2(label) {
      return `<span class='title'>${label}</span>`;
    },
    fnOnGrouped() {
      // Hide default set group rows
      $(
        '#latest_builds_table tbody tr[id^=group-id-latest_builds_table_][id$=--]',
      ).hide();
    },
  });

  // applyHovering('latest_builds_table');
}

$(document).ready(() => {
  const pathname = window.location.pathname.substring(
    window.location.pathname.lastIndexOf('/') + 1,
  );
  if (pathname === '') {
    pageType = 'index';
  } else {
    pageType = pathname.substr(0, pathname.length - 5);
  }

  if (pageType === 'build') {
    if (serverStyle === 'hosted') {
      pageMasterName = getParameterByName('mastername');
      pageBuildName = getParameterByName('build');
      if (!pageMasterName || !pageBuildName) {
        $('#loading p')
          .text('Invalid request. Mastername and Build required.')
          .addClass('error');
        return;
      }
      dataURL = `data/${pageMasterName}/${pageBuildName}/`;
      $('a.data_url').each(() => {
        const href = $(this).attr('href');
        $(this).attr('href', dataURL + href);
      });
      $('#master_link').attr('href', jailURL(pageMasterName));
    } else if (serverStyle === 'inline') {
      $('#master_link').attr('href', '../');
      $('#index_link').attr('href', '../../');
    }
    setup_build();
  } else if (pageType === 'jail') {
    if (serverStyle === 'hosted') {
      pageMasterName = getParameterByName('mastername');
      if (!pageMasterName) {
        $('#loading p')
          .text('Invalid request. Mastername required.')
          .addClass('error');
        return;
      }
      dataURL = `data/${pageMasterName}/`;
      $('a.data_url').each(() => {
        const href = $(this).attr('href');
        $(this).attr('href', dataURL + href);
      });
      $('#latest_url').attr('href', buildURL(pageMasterName, 'latest'));
    } else if (serverStyle === 'inline') {
      $('#index_link').attr('href', '../');
    }
    setup_jail();
  } else if (pageType === 'index') {
    if (serverStyle === 'hosted') {
      dataURL = 'data/';
      $('a.data_url').each(() => {
        const href = $(this).attr('href');
        $(this).attr('href', dataURL + href);
      });
    }
    setup_index();
  } else {
    $('#loading p')
      .text(`Invalid request. Unhandled page type '${pageType}'`)
      .addClass('error');
    return;
  }

  /* Activate tooltip hovers */
  $('[data-toggle="tooltip"]').tooltip();

  /* Fix nav links to not skip hashchange event when clicking multiple
   * times. */
  $('#header .nav a[href^="#"]').each(() => {
    const href = $(this).attr('href');
    if (href !== '#') {
      $(this).on('click', (e) => {
        e.preventDefault();
        if (window.location.hash !== href) {
          window.location.hash = href;
        }
        scrollToElement(href);
      });
    }
  });
  /* Force minimum width on mobile, will zoom to fit. */
  $(window).on('orientationchange', () => {
    fix_viewport();
  });
  fix_viewport();
  /* Handle resize needs */
  $(window).on('resize', () => {
    do_resize($(this));
  });
  do_resize($(window));

  update_data();
});

$(document).on('keydown', (e) => {
  /* Disable F5 refreshing since this is AJAX driven. */
  if (e.which === 116) {
    e.preventDefault();
  }
});
