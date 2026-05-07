window.buildMonitorConfig = {
    title: 'Unreal Build Monitor',
    subtitle: 'Real-time Unreal Engine Compilation Status',
    statusFile: 'build_status.js',
    refreshMs: 1000,
    notifications: {
        browser: true
    },
    projects: [
        {
            id: 'default',
            name: 'Default Project',
            title: 'Unreal Build Monitor',
            subtitle: 'Real-time Unreal Engine Compilation Status',
            statusFile: 'build_status.js'
        }
    ]
};
