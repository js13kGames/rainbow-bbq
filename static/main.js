(async () => {
    /** @type {WebGL2RenderingContext} */
    const gl = c.getContext("webgl2", {
        antialias: false,
    });
    if (!gl) throw new Error("WebGL2 not available");

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.enable(gl.CULL_FACE);
    gl.blendFunc(
        gl.SRC_ALPHA,
        gl.ONE_MINUS_SRC_ALPHA,
    );

    // Create vertex shader
    const shaderV = gl.createShader(gl.VERTEX_SHADER);
    gl.shaderSource(shaderV, await (await fetch("shader.vert.glsl")).text());
    gl.compileShader(shaderV);

    if (l = gl.getShaderInfoLog(shaderV)) {
        console.error("vertex: " + l);
    }

    // Create fragment shader
    const shaderF = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(shaderF, await (await fetch("shader.frag.glsl")).text());
    gl.compileShader(shaderF);

    if (l = gl.getShaderInfoLog(shaderF)) {
        console.error("fragment: " + l);
    }

    // Link shaders into a program
    const program = gl.createProgram();
    gl.attachShader(program, shaderV);
    gl.attachShader(program, shaderF);
    gl.linkProgram(program);
    gl.useProgram(program);

    // Create vertex buffer (singular)
    const vertexBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, vertexBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, 0x400000, gl.DYNAMIC_DRAW);

    // Set up vertex state (no VAO or anything, we straight ballin')
    let i = 0;
    gl.enableVertexAttribArray(i++);
    gl.enableVertexAttribArray(i++);
    gl.enableVertexAttribArray(i++);
    gl.enableVertexAttribArray(i++);
    gl.vertexAttribPointer(0, 4, gl.FLOAT, false, 32, 0);
    gl.vertexAttribPointer(1, 2, gl.FLOAT, false,  32, 16);
    gl.vertexAttribPointer(2, 4, gl.UNSIGNED_BYTE, true, 32, 24);
    gl.vertexAttribPointer(3, 4, gl.UNSIGNED_BYTE, true, 32, 28);

    // Instantiate WASM module
    const wasmMemory = new WebAssembly.Memory({initial: 1000});
    const module = await WebAssembly.compile(await (await fetch(0)).arrayBuffer());
    const instance = await WebAssembly.instantiate(module, {"": [
        /*  0: memory       */  wasmMemory,
        /*  1: log          */  (logLevel, strPtr, strLen) => console[["error", "warn", "info", "debug"][logLevel]]((new TextDecoder()).decode(new Uint8Array(wasmMemory.buffer, strPtr, strLen))),
        /*  2: draw         */  (vertexPtr, numVerts) => {
            gl.bufferSubData(gl.ARRAY_BUFFER, 0, new Uint8Array(wasmMemory.buffer, vertexPtr, numVerts * 32));
            gl.drawArrays(gl.TRIANGLES, 0, numVerts);
            gl.clear(gl.DEPTH_BUFFER_BIT);
        },
        /*  3: texUpload    */  (dataPtr, texWidth, texHeight) => {
            const texture = gl.createTexture();
            gl.activeTexture(gl.TEXTURE0);
            gl.bindTexture(gl.TEXTURE_2D, texture);

            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
            
            gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8UI, texWidth, texHeight, 0, gl.RED_INTEGER, gl.UNSIGNED_BYTE, new Uint8Array(wasmMemory.buffer, dataPtr, texWidth * texHeight));
            gl.uniform1i(gl.getUniformLocation(program, "s"), 0);
        },
        /*  4: Math.atan2   */  Math.atan2,
        /*  5: Math.sin     */  Math.sin,
        /*  6: Math.cos     */  Math.cos,
        /*  7: Math.tan     */  Math.tan,
    ]});

    // Register inputs
    addEventListener("keydown", (event) => {
        instance.exports.k(event.keyCode, true);
    });
    addEventListener("keyup", (event) => {
        instance.exports.k(event.keyCode, false);
    });

    onmousemove = (event) => {
        if (event.buttons) {
            instance.exports.m(event.movementX, event.movementY);
        }
    };

    // Run once per frame
    instance.exports.a();
    const interval = setInterval(() => {
        try {
            gl.clearColor(0.5, 0.34, 0.8, 1.0);
            gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

            instance.exports.b();

            gl.flush();
        } catch (err) {
            clearInterval(interval);
            throw err;
        }
    }, 1000 / 60);
})();
