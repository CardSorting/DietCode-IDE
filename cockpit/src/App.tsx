import { ApprovalPanel } from './components/ApprovalPanel';
import { ChatPanel } from './components/ChatPanel';
import { DiffPanel } from './components/DiffPanel';
import { LogStream } from './components/LogStream';
import { TaskTimeline } from './components/TaskTimeline';
import { useKernel } from './hooks/useKernel';

export default function App() {
  const { status, events, timeline } = useKernel();

  return (
    <div className="app">
      <header className="header">
        <div>
          <h1>DietCode Cockpit</h1>
          <p className="tagline">Local control plane for agentic software work</p>
        </div>
        <div>
          <span className={`status-pill ${status.connected ? 'connected' : 'disconnected'}`}>
            {status.connected ? 'Kernel connected' : 'Kernel offline'}
          </span>
          {status.workspace ? (
            <p className="tagline" style={{ textAlign: 'right', marginTop: '0.25rem' }}>
              {status.workspace}
            </p>
          ) : null}
        </div>
      </header>

      <div className="layout">
        <section className="panel">
          <div className="panel-header">Chat</div>
          <ChatPanel />
        </section>

        <section className="panel">
          <div className="panel-header">Task Timeline</div>
          <div className="panel-body">
            <TaskTimeline events={events} timeline={timeline} />
          </div>
          <div className="panel-header">Diffs</div>
          <div className="panel-body">
            <DiffPanel />
          </div>
        </section>

        <section className="panel">
          <div className="panel-header">Approvals</div>
          <div className="panel-body">
            <ApprovalPanel events={events} />
          </div>
          <div className="panel-header">Logs</div>
          <div className="panel-body">
            <LogStream events={events} />
          </div>
        </section>
      </div>
    </div>
  );
}
