import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/errors/error_display.dart';
import '../build_job_provider.dart';
import '../models/build_job.dart';

/// Build mode's workspace panel — sits above the message input, only
/// ever visible in Build mode and only once a build has actually
/// started (see [BuildJobProvider.job]). Shows a live progress
/// checklist while building, then the generated file tree with
/// [View file] / [Download ZIP] once it's done — never a redesign of
/// the conversation screen itself, just one extra panel slotted in.
class BuildWorkspacePanel extends StatelessWidget {
  const BuildWorkspacePanel({super.key, required this.provider});

  final BuildJobProvider provider;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        final job = provider.job;
        if (job == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.build.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(job: job, onDismiss: provider.reset),
              const SizedBox(height: 10),
              if (job.isFailed)
                _FailedState(job: job)
              else if (job.isCompleted)
                _CompletedState(provider: provider, job: job)
              else
                _ProgressChecklist(job: job),
              if (provider.errorMessage != null) ...[
                const SizedBox(height: 8),
                ErrorBanner(message: provider.errorMessage!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.job, required this.onDismiss});

  final BuildJob job;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = job.projectType == 'chrome_extension' ? Icons.extension_rounded : Icons.code_rounded;
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.build),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            job.projectName,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Only dismissible once the build is done (or failed) — hiding
        // an in-progress build would just leave the user unsure whether
        // it's still running.
        if (job.isTerminal)
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _ProgressChecklist extends StatelessWidget {
  const _ProgressChecklist({required this.job});

  final BuildJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex = job.stepIndex;
    // FIXING only shows up if validation actually failed once — skip it
    // from the checklist for the common path where it's never reached,
    // rather than showing a step that will just sit permanently unchecked.
    final steps = currentIndex >= BuildJob.progressSteps.indexOf('FIXING')
        ? BuildJob.progressSteps
        : (List<String>.from(BuildJob.progressSteps)..remove('FIXING'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                _StepIcon(done: BuildJob.progressSteps.indexOf(step) < currentIndex, current: step == job.status),
                const SizedBox(width: 8),
                Text(
                  BuildJob.label(step),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: step == job.status ? FontWeight.w600 : FontWeight.normal,
                    color: step == job.status
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.done, required this.current});

  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    if (done) return const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success);
    if (current) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.build),
      );
    }
    return Icon(Icons.circle_outlined, size: 16, color: Theme.of(context).colorScheme.outlineVariant);
  }
}

class _FailedState extends StatelessWidget {
  const _FailedState({required this.job});

  final BuildJob job;

  @override
  Widget build(BuildContext context) {
    return ErrorBanner(message: job.error ?? 'The build failed for an unknown reason.');
  }
}

class _CompletedState extends StatelessWidget {
  const _CompletedState({required this.provider, required this.job});

  final BuildJobProvider provider;
  final BuildJob job;

  Future<void> _download(BuildContext context) async {
    final url = provider.artifactDownloadUrl();
    if (url == null) return;
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault, webOnlyWindowName: '_blank');
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the download. Try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.success),
            const SizedBox(width: 8),
            Text('Build completed', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 10),
        if (provider.isLoadingFiles)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (provider.files.isEmpty)
          Text('No files were listed for this build.', style: theme.textTheme.bodySmall)
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: provider.files.length,
              itemBuilder: (context, index) {
                final path = provider.files[index];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
                  title: Text(path, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                  onTap: () => _showFile(context, path),
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        if (job.hasArtifact) ...[
          if (provider.artifactAutoDownloaded)
            Text(
              '${job.projectName}.zip downloaded automatically.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              // Still shown even after the automatic download -- a
              // browser popup blocker can silently swallow that one
              // (it fires from a background timer, not a click), and
              // it's a harmless re-download either way.
              OutlinedButton.icon(
                onPressed: () => _download(context),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  provider.artifactAutoDownloaded
                      ? 'Download again'
                      : 'Download ${job.projectName}.zip',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showFile(BuildContext context, String path) {
    provider.selectFile(path);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FileContentSheet(provider: provider, path: path),
    );
  }
}

class _FileContentSheet extends StatelessWidget {
  const _FileContentSheet({required this.provider, required this.path});

  final BuildJobProvider provider;
  final String path;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: provider,
      builder: (context, _) {
        final theme = Theme.of(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(path, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const Divider(height: 20),
                  Expanded(
                    child: provider.isLoadingFileContent
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            controller: scrollController,
                            child: SelectableText(
                              provider.selectedFileContent ?? '',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
