{
  alertmanager_config:: {
    templates: ['/etc/alertmanager/*.tmpl'],
    route: {
      group_by: ['alertname'],
      receiver: 'slack',
    },

    receivers: [{
      name: 'slack',
      slack_configs: [{
        api_url: $._config.slack_url,
        channel: $._config.slack_channel,
      }],
    }],
  },

  local configMap = $.core.v1.configMap,

  alertmanager_config_map:
    configMap.new('alertmanager-config') +
    configMap.withData({
      'alertmanager.yml': $.util.manifestYaml($.alertmanager_config),
    }),

  local container = $.core.v1.container,
  local volumeMount = $.core.v1.volumeMount,

  alertmanager_container::
    container.new('alertmanager', $._images.alertmanager) +
    container.withPorts($.core.v1.containerPort.new('http-metrics', $._config.alertmanager_port)) +
    container.withArgs([
      '--log.level=info',
      '--config.file=/etc/alertmanager/config/alertmanager.yml',
      '--web.listen-address=:%s' % $._config.alertmanager_port,
      '--web.external-url=%s%s' % [$._config.alertmanager_external_hostname, $._config.alertmanager_path],
      '--storage.path=/alertmanager',
    ]) +
    container.withVolumeMountsMixin(
      volumeMount.new('alertmanager-data', '/alertmanager')
    ) +
    container.mixin.resources.withRequests({
      cpu: '10m',
      memory: '40Mi',
    }),

  alertmanager_watch_container::
    container.new('watch', $._images.watch) +
    container.withArgs([
      '-v',
      '-t',
      '-p=/etc/alertmanager/config',
      'curl',
      '-X',
      'POST',
      '--fail',
      '-o',
      '-',
      '-sS',
      'http://localhost:%s%s-/reload' % [$._config.alertmanager_port, $._config.alertmanager_path],
    ]) +
    container.mixin.resources.withRequests({
      cpu: '10m',
      memory: '20Mi',
    }),

  local pvc = $.core.v1.persistentVolumeClaim,

  alertmanager_pvc::
    pvc.new() +
    pvc.mixin.metadata.withName('alertmanager-data') +
    pvc.mixin.spec.withAccessModes('ReadWriteOnce') +
    pvc.mixin.spec.resources.withRequests({ storage: '5Gi' }),

  local statefulset = $.apps.v1beta1.statefulSet,

  alertmanager_statefulset:
    statefulset.new('alertmanager', 1, [
      $.alertmanager_container,
      $.alertmanager_watch_container,
    ], self.alertmanager_pvc) +
    statefulset.mixin.spec.template.metadata.withAnnotations({ 'prometheus.io.path': '%smetrics' % $._config.alertmanager_path }) +
    statefulset.mixin.spec.template.spec.securityContext.withRunAsUser(0) +
    statefulset.mixin.spec.template.spec.securityContext.withFsGroup(0) +
    $.util.configVolumeMount('alertmanager-config', '/etc/alertmanager/config') +
    $.util.podPriority('critical'),

  alertmanager_service:
    $.util.serviceFor($.alertmanager_statefulset),
}
