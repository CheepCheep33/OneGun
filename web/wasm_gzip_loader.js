// Cloudflare Pages rejects files over 25 MiB and Godot's engine .wasm is ~34 MiB, so the deploy
// workflow ships it gzipped as index.wasm.gz.bin. This wraps fetch so the engine loader still
// receives a normal application/wasm response, decompressed in the browser.
(function () {
	if (!('DecompressionStream' in window)) {
		return;
	}
	const realFetch = window.fetch.bind(window);
	window.fetch = function (input, init) {
		const url = typeof input === 'string' ? input : input.url;
		if (!/\.wasm(\?|$)/.test(url)) {
			return realFetch(input, init);
		}
		return realFetch(url.replace(/\.wasm(?=\?|$)/, '.wasm.gz.bin'), init).then(function (response) {
			if (!response.ok) {
				return realFetch(input, init);
			}
			const body = response.body.pipeThrough(new DecompressionStream('gzip'));
			return new Response(body, { status: 200, headers: { 'Content-Type': 'application/wasm' } });
		});
	};
})();
