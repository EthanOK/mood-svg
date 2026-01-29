function parseTokenURI(tokenURI: string) {
  // 移除前缀 "data:application/json;base64,"
  const base64Data = tokenURI.replace("data:application/json;base64,", "");

  // 解码 base64
  const decodedJson = Buffer.from(base64Data, "base64").toString("utf8");

  return decodedJson;
}

async function main() {
  const tokenURI = process.argv[2];
  if (!tokenURI) {
    console.error("请提供 tokenURI 参数");
    return;
  }

  const jsonString = parseTokenURI(tokenURI);
  console.log(jsonString);
}

main().catch(console.error);

// ts-node scripts/parseTokenURI.ts 'data:application/json;base64,eyJuYW1lIjogIkJBWUMgIzE4IiwgImRlc2NyaXB0aW9uIjogIkEgU1ZHIE5GVCEiLCAiYXR0cmlidXRlcyI6IFt7InRyYWl0X3R5cGUiOiAiTW9vZCIsICJ2YWx1ZSI6IDI1fV0sICJpbWFnZSI6ICJkYXRhOmltYWdlL3N2Zyt4bWw7YmFzZTY0LFBITjJaeUIyYVdWM1FtOTRQU0l3SURBZ01qQXdJREl3TUNJZ2QybGtkR2c5SWpRd01DSWdJR2hsYVdkb2REMGlOREF3SWlCNGJXeHVjejBpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TWpBd01DOXpkbWNpUGdvZ0lEeGphWEpqYkdVZ1kzZzlJakV3TUNJZ1kzazlJakV3TUNJZ1ptbHNiRDBpZVdWc2JHOTNJaUJ5UFNJM09DSWdjM1J5YjJ0bFBTSmliR0ZqYXlJZ2MzUnliMnRsTFhkcFpIUm9QU0l6SWk4K0NpQWdQR2NnWTJ4aGMzTTlJbVY1WlhNaVBnb2dJQ0FnUEdOcGNtTnNaU0JqZUQwaU5qRWlJR041UFNJNE1pSWdjajBpTVRJaUx6NEtJQ0FnSUR4amFYSmpiR1VnWTNnOUlqRXlOeUlnWTNrOUlqZ3lJaUJ5UFNJeE1pSXZQZ29nSUR3dlp6NEtJQ0E4Y0dGMGFDQmtQU0p0TVRNMkxqZ3hJREV4Tmk0MU0yTXVOamtnTWpZdU1UY3ROalF1TVRFZ05ESXRPREV1TlRJdExqY3pJaUJ6ZEhsc1pUMGlabWxzYkRwdWIyNWxPeUJ6ZEhKdmEyVTZJR0pzWVdOck95QnpkSEp2YTJVdGQybGtkR2c2SURNN0lpOCtDand2YzNablBnPT0ifQ=='
