// Operator report charts read the adjacent fallback table, so no inline JSON is needed.
(function () {
	function tokenColor(name, fallback) {
		if (typeof getComputedStyle !== 'function') {
			return fallback;
		}
		var value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
		return value || fallback;
	}

	// 팔레트(#2349 PR⑩e): admin 대시보드 추이 차트(dashboard-charts.js PALETTE)와 동일한 순서 —
	// 파랑(주 계열) → 잉크 톤(보조) → 잉크 톤(보조2) → 경고색. 상태 의미 없는 카테고리 막대에
	// 상태색(good=초록/청록 계열)을 대표색으로 쓰지 않는다.
	var COLORS = [
		tokenColor('--admin-accent', '#006fd6'),
		tokenColor('--admin-ink-2', '#29484b'),
		tokenColor('--admin-ink-3', '#466467'),
		tokenColor('--admin-danger', '#b42318')
	];

	function tableData(canvas) {
		var tableId = canvas.getAttribute('data-operator-chart-table');
		var table = tableId ? document.getElementById(tableId) : null;
		if (!table) {
			return null;
		}
		var labels = [];
		var values = [];
		table.querySelectorAll('tbody tr').forEach(function (row) {
			var cells = row.querySelectorAll('td');
			if (cells.length < 2) {
				return;
			}
			labels.push(cells[0].textContent.trim());
			values.push(Number(cells[1].textContent.trim().replace(/,/g, '')) || 0);
		});
		return { labels: labels, values: values };
	}

	function render(canvas) {
		if (!window.Chart) {
			return;
		}
		var data = tableData(canvas);
		if (!data || data.labels.length === 0) {
			return;
		}
		if (canvas.chartInstance) {
			canvas.chartInstance.destroy();
		}
		var type = canvas.getAttribute('data-operator-chart') || 'bar';
		canvas.chartInstance = new window.Chart(canvas, {
			type: type,
			data: {
				labels: data.labels,
				datasets: [{
					label: '건수',
					data: data.values,
					backgroundColor: COLORS,
					borderColor: COLORS
				}]
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				plugins: { legend: { display: type !== 'bar', position: 'bottom' } },
				scales: type === 'bar' ? { y: { beginAtZero: true } } : {}
			}
		});
	}

	document.addEventListener('DOMContentLoaded', function () {
		document.querySelectorAll('canvas[data-operator-chart]').forEach(render);
	});
})();
