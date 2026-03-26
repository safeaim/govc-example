import { createBackendModule } from '@backstage/backend-plugin-api';
import { coreServices } from '@backstage/backend-plugin-api';
import { scaffolderActionsExtensionPoint } from '@backstage/plugin-scaffolder-node/alpha';
import { createTemplateAction } from '@backstage/plugin-scaffolder-node';
import { z } from 'zod';

/**
 * Backstage scaffolder action that posts a namespace-order event to the
 * Argo Events webhook, triggering the namespace-provisioner WorkflowTemplate.
 *
 * Configure the webhook URL in app-config.yaml:
 *
 *   argoEvents:
 *     webhookUrl: http://localhost:12000/namespace-request
 *
 * Port-forward the Argo Events service to reach it from the host:
 *   kubectl -n argo-events port-forward svc/backstage-webhook-eventsource-svc 12000:12000
 */
export const argoEventsModule = createBackendModule({
  pluginId: 'scaffolder',
  moduleId: 'argo-events',
  register(reg) {
    reg.registerInit({
      deps: {
        scaffolderActions: scaffolderActionsExtensionPoint,
        config: coreServices.rootConfig,
        logger: coreServices.logger,
      },
      async init({ scaffolderActions, config, logger }) {
        scaffolderActions.addActions(
          createTemplateAction({
            id: 'platform:argo-events:trigger',
            description:
              'Posts a namespace-order event to the Argo Events webhook to trigger the provisioning workflow.',
            schema: {
              input: z.object({
                namespace: z
                  .string()
                  .regex(/^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$/)
                  .describe('Target Kubernetes namespace name'),
                team: z
                  .string()
                  .describe('Team name used as the RBAC Group subject'),
                cpuLimit: z
                  .string()
                  .describe('CPU limit, e.g. "2" (cores)'),
                memoryLimit: z
                  .string()
                  .describe('Memory limit, e.g. "4Gi"'),
                requestMinio: z
                  .boolean()
                  .default(false)
                  .describe('Whether to create a MinIO bucket'),
                requestPostgres: z
                  .boolean()
                  .default(false)
                  .describe('Whether to create a PostgreSQL StatefulSet'),
              }),
            },
            async handler(ctx) {
              const webhookUrl = config.getString('argoEvents.webhookUrl');

              ctx.logger.info(
                `Triggering namespace provisioning for ${ctx.input.namespace} via ${webhookUrl}`,
              );

              const body = {
                namespace: ctx.input.namespace,
                team: ctx.input.team,
                cpuLimit: ctx.input.cpuLimit,
                memoryLimit: ctx.input.memoryLimit,
                requestMinio: ctx.input.requestMinio,
                requestPostgres: ctx.input.requestPostgres,
              };

              const response = await fetch(webhookUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body),
              });

              if (!response.ok) {
                const text = await response.text().catch(() => '');
                throw new Error(
                  `Argo Events webhook returned ${response.status}: ${text}`,
                );
              }

              ctx.logger.info(
                `Namespace provisioning workflow triggered successfully for ${ctx.input.namespace}`,
              );
            },
          }),
        );

        logger.info('Registered scaffolder action: platform:argo-events:trigger');
      },
    });
  },
});
