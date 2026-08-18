import { Container } from "@cloudflare/containers";

export class CobaltContainer extends Container<Env> {
  override defaultPort = 9000;
  override sleepAfter = "10m";
  override enableInternet = true;
  override envVars = {
    API_URL: `${this.env.PUBLIC_BASE_URL.replace(/\/$/, "")}/v1/cobalt/`,
  };

  override onStart(): void {
    console.log(JSON.stringify({ event: "cobalt_container_started" }));
  }

  override onStop({ exitCode, reason }: { exitCode: number; reason: string }): void {
    console.log(JSON.stringify({ event: "cobalt_container_stopped", exitCode, reason }));
  }

  override onError(error: unknown): void {
    console.error(
      JSON.stringify({
        event: "cobalt_container_error",
        message: error instanceof Error ? error.message : "unknown",
      }),
    );
  }
}
