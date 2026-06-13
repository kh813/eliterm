let Hooks = {};

Hooks.Terminal = {
  mounted() {
    this.term = new window.Terminal({
      cursorBlink: true,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      fontSize: 14,
      theme: {
        background: 'transparent',
        foreground: '#e5e5e5',
        cursor: '#4ade80'
      }
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
      this.term.write(payload.data);
    });

    // Resize handling
    window.addEventListener("resize", () => {
      this.fitAddon.fit();
      this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
    });
    
    // Initial resize trigger
    setTimeout(() => {
        this.fitAddon.fit();
        this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
    }, 100);
  }
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
});

liveSocket.connect();
