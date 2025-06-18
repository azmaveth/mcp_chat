// MCP Chat Web UI JavaScript

// Auto-scroll chat messages to bottom
function scrollChatToBottom() {
  const messagesContainer = document.querySelector('.messages-container');
  if (messagesContainer) {
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
  }
}

// Auto-scroll when new messages are added
const observer = new MutationObserver(function(mutations) {
  mutations.forEach(function(mutation) {
    if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
      // Check if the added node is a chat message
      const addedMessage = Array.from(mutation.addedNodes).find(node => 
        node.classList && node.classList.contains('chat-message')
      );
      if (addedMessage) {
        scrollChatToBottom();
      }
    }
  });
});

// Start observing when page loads
document.addEventListener('DOMContentLoaded', function() {
  const messagesContainer = document.querySelector('.messages-container');
  if (messagesContainer) {
    // Initial scroll to bottom
    scrollChatToBottom();
    
    // Start observing for new messages
    observer.observe(messagesContainer, {
      childList: true,
      subtree: true
    });
  }
  
  // Auto-focus on message input
  const messageInput = document.querySelector('input[name="message"]');
  if (messageInput) {
    messageInput.focus();
  }
  
  // Handle Enter key in message input
  if (messageInput) {
    messageInput.addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const form = messageInput.closest('form');
        if (form) {
          form.dispatchEvent(new Event('submit', { bubbles: true }));
        }
      }
    });
  }
  
  // Handle Enter key in command input
  const commandInput = document.querySelector('input[name="command"]');
  if (commandInput) {
    commandInput.addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const form = commandInput.closest('form');
        if (form) {
          form.dispatchEvent(new Event('submit', { bubbles: true }));
        }
      }
    });
  }
});

// Real-time clock for dashboard
function updateClock() {
  const clockElements = document.querySelectorAll('.live-clock');
  clockElements.forEach(function(element) {
    const now = new Date();
    element.textContent = now.toLocaleTimeString();
  });
}

// Update clock every second
setInterval(updateClock, 1000);

// Handle tab switching
function showTab(tabName) {
  // Hide all tab content
  const tabContents = document.querySelectorAll('.tab-content');
  tabContents.forEach(content => content.style.display = 'none');
  
  // Remove active class from all tabs
  const tabs = document.querySelectorAll('.tab');
  tabs.forEach(tab => tab.classList.remove('active'));
  
  // Show selected tab content
  const selectedContent = document.getElementById(tabName);
  if (selectedContent) {
    selectedContent.style.display = 'block';
  }
  
  // Add active class to clicked tab
  const selectedTab = document.querySelector(`[data-tab="${tabName}"]`);
  if (selectedTab) {
    selectedTab.classList.add('active');
  }
}

// Toast notifications
function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  
  // Style the toast
  Object.assign(toast.style, {
    position: 'fixed',
    top: '20px',
    right: '20px',
    padding: '12px 20px',
    borderRadius: '4px',
    color: 'white',
    fontWeight: '500',
    zIndex: '1000',
    opacity: '0',
    transition: 'opacity 0.3s ease'
  });
  
  // Set background color based on type
  const colors = {
    info: '#3b82f6',
    success: '#059669',
    warning: '#d97706',
    error: '#dc2626'
  };
  toast.style.backgroundColor = colors[type] || colors.info;
  
  document.body.appendChild(toast);
  
  // Animate in
  setTimeout(() => toast.style.opacity = '1', 100);
  
  // Auto-remove after 3 seconds
  setTimeout(() => {
    toast.style.opacity = '0';
    setTimeout(() => document.body.removeChild(toast), 300);
  }, 3000);
}

// Keyboard shortcuts
document.addEventListener('keydown', function(e) {
  // Ctrl/Cmd + Enter to send message quickly
  if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
    const messageForm = document.querySelector('form[phx-submit="send_message"]');
    if (messageForm) {
      messageForm.dispatchEvent(new Event('submit', { bubbles: true }));
    }
  }
  
  // Escape to clear current input
  if (e.key === 'Escape') {
    const activeInput = document.activeElement;
    if (activeInput && (activeInput.tagName === 'INPUT' || activeInput.tagName === 'TEXTAREA')) {
      activeInput.value = '';
      activeInput.blur();
    }
  }
});

// Copy to clipboard functionality
function copyToClipboard(text) {
  navigator.clipboard.writeText(text).then(() => {
    showToast('Copied to clipboard', 'success');
  }).catch(() => {
    showToast('Failed to copy', 'error');
  });
}

// Add copy buttons to code blocks (if any)
document.addEventListener('DOMContentLoaded', function() {
  const codeBlocks = document.querySelectorAll('pre, code');
  codeBlocks.forEach(function(block) {
    if (block.textContent.length > 20) {
      const copyButton = document.createElement('button');
      copyButton.textContent = 'Copy';
      copyButton.className = 'btn btn-sm';
      copyButton.style.cssText = 'position: absolute; top: 5px; right: 5px; font-size: 0.75rem; padding: 0.25rem 0.5rem;';
      
      copyButton.addEventListener('click', function() {
        copyToClipboard(block.textContent);
      });
      
      // Make parent relative for absolute positioning
      block.style.position = 'relative';
      block.appendChild(copyButton);
    }
  });
});

// Auto-refresh functionality for pages that need it
function enableAutoRefresh(intervalMs = 30000) {
  setInterval(function() {
    // Only refresh if page is visible and user isn't actively typing
    if (!document.hidden && !document.activeElement.matches('input, textarea')) {
      const refreshButton = document.querySelector('[phx-click="refresh_all"], [phx-click="refresh_agents"], [phx-click="refresh_sessions"]');
      if (refreshButton) {
        refreshButton.click();
      }
    }
  }, intervalMs);
}

// Start auto-refresh on dashboard and monitor pages
document.addEventListener('DOMContentLoaded', function() {
  const pathname = window.location.pathname;
  if (pathname === '/' || pathname.includes('/agents') || pathname === '/sessions') {
    enableAutoRefresh(30000); // Refresh every 30 seconds
  }
});

// Handle Phoenix LiveView reconnection
window.addEventListener('phx:page-loading-start', () => {
  showToast('Connecting...', 'info');
});

window.addEventListener('phx:page-loading-stop', () => {
  showToast('Connected', 'success');
});

// Export functions for global use
window.MCPChat = {
  showToast,
  copyToClipboard,
  showTab,
  scrollChatToBottom
};