let Hooks = {};

Hooks.Terminal = {
  mounted() {
    let colors = JSON.parse(this.el.dataset.colors || "{}");
    this.term = new window.Terminal({
      cursorBlink: true,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      fontSize: 14,
      theme: Object.assign({
        background: 'transparent',
        foreground: '#e5e5e5',
        cursor: '#4ade80'
      }, colors)
    });

    this.fitAddon = new window.FitAddon.FitAddon();
    this.term.loadAddon(this.fitAddon);

    this.term.open(this.el);
    this.fitAddon.fit();

    // Handle terminal input
    this.term.onData(data => {
      this.pushEvent("terminal_input", { data: data });
    });

    // Handle incoming data from Elixir
    this.handleEvent("terminal_output", payload => {
      // Decode Base64 to Uint8Array
      const binaryString = atob(payload.data);
      const len = binaryString.length;
      const bytes = new Uint8Array(len);
      for (let i = 0; i < len; i++) {
        bytes[i] = binaryString.charCodeAt(i);
      }
      this.term.write(bytes);
    });

    // Handle incoming theme updates
    this.handleEvent("terminal_theme", payload => {
      let colors = payload.colors;
      this.term.options.theme = Object.assign({
        background: 'transparent',
        foreground: '#e5e5e5',
        cursor: '#4ade80'
      }, colors);
    });

    // Resize handling using ResizeObserver (robust for dynamically sized containers)
    const resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit();
      this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
    });
    resizeObserver.observe(this.el);

    // Initial resize
    setTimeout(() => {
      this.fitAddon.fit();
      this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
      window.focus();
      this.term.focus();
    }, 100);

    // Custom Key Event Handler for Copy & Paste
    this.term.attachCustomKeyEventHandler(async (e) => {
      // Cmd+C or Ctrl+C to copy if text is selected
      if (e.type === 'keydown' && e.key === 'c' && (e.metaKey || e.ctrlKey)) {
        if (this.term.hasSelection()) {
          navigator.clipboard.writeText(this.term.getSelection());
          return false; // Prevent default so it doesn't send Ctrl+C to the shell if selected
        }
      }
      
      // Cmd+V or Ctrl+V to paste
      if (e.type === 'keydown' && e.key === 'v' && (e.metaKey || e.ctrlKey)) {
        try {
          const text = await navigator.clipboard.readText();
          this.pushEvent("terminal_input", { data: text });
        } catch (err) {
          console.error("Failed to read clipboard: ", err);
        }
        return false;
      }
      return true;
    });
  }
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
});

liveSocket.connect();
