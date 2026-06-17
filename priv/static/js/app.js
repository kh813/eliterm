let Hooks = {};

Hooks.Terminal = {
  mounted() {
    let colors = JSON.parse(this.el.dataset.colors || "{}");
    const defaultFont = 'Consolas, "Cascadia Code", Menlo, Monaco, "Courier New", monospace';
    const userFont = this.el.dataset.font;
    const finalFont = userFont ? `"${userFont}", ${defaultFont}` : defaultFont;

    this.term = new window.Terminal({
      cursorBlink: true,
      fontFamily: finalFont,
      fontSize: 14,
      allowTransparency: false,
      theme: Object.assign({
        background: '#000000',
        foreground: '#e5e5e5',
        cursor: '#4ade80',
        selectionBackground: 'rgba(255, 255, 255, 0.3)'
      }, colors),
      macOptionClickForcesSelection: true,
      macOptionIsMeta: true
    });
    
    if (colors.background) {
      this.el.parentElement.style.backgroundColor = colors.background;
      this.el.parentElement.parentElement.style.backgroundColor = colors.background;
    } else {
      this.el.parentElement.style.backgroundColor = '#000000';
      this.el.parentElement.parentElement.style.backgroundColor = '#000000';
    }

    this.fitAddon = new window.FitAddon.FitAddon();
    this.term.loadAddon(this.fitAddon);

    this.term.open(this.el);
    this.fitAddon.fit();
    
    // Ensure correct alignment after fonts load
    if (document.fonts) {
      document.fonts.ready.then(() => {
        this.fitAddon.fit();
        this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
      });
    }

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
        background: '#000000',
        foreground: '#e5e5e5',
        cursor: '#4ade80',
        selectionBackground: 'rgba(255, 255, 255, 0.3)'
      }, colors);
      
      if (colors.background) {
        this.el.parentElement.style.backgroundColor = colors.background;
        this.el.parentElement.parentElement.style.backgroundColor = colors.background;
      } else {
        this.el.parentElement.style.backgroundColor = '#000000';
        this.el.parentElement.parentElement.style.backgroundColor = '#000000';
      }
    });

    // Handle incoming font updates
    this.handleEvent("terminal_font", payload => {
      const defaultFont = 'Consolas, "Cascadia Code", Menlo, Monaco, "Courier New", monospace';
      const userFont = payload.font;
      const finalFont = userFont ? `"${userFont}", ${defaultFont}` : defaultFont;
      this.term.options.fontFamily = finalFont;
      
      // Ensure correct alignment after fonts load
      if (document.fonts) {
        document.fonts.ready.then(() => {
          this.fitAddon.fit();
          this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
        });
      } else {
        this.fitAddon.fit();
        this.pushEvent("terminal_resize", { cols: this.term.cols, rows: this.term.rows });
      }
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
    this.term.attachCustomKeyEventHandler((e) => {
      const isCopy = (e.ctrlKey || e.metaKey) && e.code === 'KeyC';
      const isPaste = (e.ctrlKey || e.metaKey) && e.code === 'KeyV';

      if (isCopy) {
        console.log("Custom key handler intercepted Copy, hasSelection:", this.term.hasSelection());
        if (this.term.hasSelection()) {
          const text = this.term.getSelection();
          console.log("Pushing clipboard_copy from key handler:", text);
          this.pushEvent("clipboard_copy", { text: text });
        }
        return false; // Prevent xterm.js / browser default copy handling (which fails)
      }

      if (isPaste) {
        // Let the OS native paste handle it naturally inside the webview (pastes once).
        // Do not push clipboard_paste to Elixir to prevent double pasting.
        return true; 
      }

      return true;
    });

    // Also listen to native copy events in case the terminal isn't perfectly focused
    window.addEventListener('copy', (e) => {
      console.log("window copy event triggered, hasSelection:", this.term.hasSelection());
      if (this.term.hasSelection()) {
        const text = this.term.getSelection();
        // Do not prevent default! Let the browser natively copy the textarea text.
        console.log("Pushing clipboard_copy event from window listener:", text);
        this.pushEvent("clipboard_copy", { text: text });
      }
    });

    // Handle incoming events from LiveView
    this.handleEvent("request_copy", () => {
      console.log("request_copy event received from LiveView, hasSelection:", this.term.hasSelection());
      if (this.term.hasSelection()) {
        const text = this.term.getSelection();
        if (navigator.clipboard) {
          navigator.clipboard.writeText(text)
            .then(() => console.log("Successfully wrote selection to navigator.clipboard"))
            .catch(err => console.error("Failed to write to navigator.clipboard:", err));
        }
        console.log("Pushing clipboard_copy event from request_copy:", text);
        this.pushEvent("clipboard_copy", { text: text });
      } else {
        console.warn("request_copy called but no selection exists in terminal");
      }
    });

    this.handleEvent("request_paste", () => {
      if (navigator.clipboard) {
        navigator.clipboard.readText().then(text => {
          this.term.paste(text);
        }).catch(() => {
          this.pushEvent("clipboard_paste", {});
        });
      } else {
        this.pushEvent("clipboard_paste", {});
      }
    });
    // Handle incoming paste events from LiveView (fallback if navigator.clipboard fails)
    this.handleEvent("terminal_paste", (payload) => {
      if (payload.text) {
        this.term.paste(payload.text);
      }
    });
  }
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken }
});

liveSocket.connect();
