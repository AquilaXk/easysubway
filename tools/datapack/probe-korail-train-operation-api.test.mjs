import assert from "node:assert/strict";
import test from "node:test";

import {
  KORAIL_TRAIN_OPERATION_APIS,
  probeKorailTrainOperationApi,
} from "./probe-korail-train-operation-api.mjs";

test("Korail 코드정보 probe는 공식 type 조건으로 호출한다", async () => {
  let requestedUrl;
  const evidence = await probeKorailTrainOperationApi({
    sourceId: "korail-train-operation-codes",
    serviceKey: "key",
    fetchImpl: async (url) => {
      requestedUrl = url;
      return new Response(JSON.stringify({
        response: {
          header: { resultCode: "0" },
          body: {
            items: { item: [{ code: "GJ", type: "mrnt_cd", value: "경춘선" }] },
            numOfRows: 10,
            pageNo: 1,
            totalCount: 1,
          },
        },
      }), { status: 200, headers: { "content-type": "application/json" } });
    },
  });

  assert.equal(requestedUrl.searchParams.get("cond[type::EQ]"), "mrnt_cd");
  assert.equal(evidence.rowCount, 1);
});

test("Korail 열차운행정보 probe는 요청과 응답 schema를 검증하고 credential을 제거한다", async () => {
  const secret = "never-print-this-key";
  let requestedUrl;
  const evidence = await probeKorailTrainOperationApi({
    sourceId: "korail-traveler-train-run-info",
    runDate: "20260713",
    serviceKey: secret,
    fetchImpl: async (url) => {
      requestedUrl = url;
      return new Response(JSON.stringify({
        response: {
          header: { resultCode: "0", resultMsg: "NORMAL SERVICE." },
          body: {
            items: {
              item: [{
                run_ymd: "20260713",
                trn_no: "02001",
                trn_run_sn: 1,
                stn_cd: "0001",
                stn_nm: "용산",
                mrnt_cd: "ITX",
                mrnt_nm: "ITX-청춘",
                uppln_dn_se_cd: "D",
                stop_se_cd: "S",
                stop_se_nm: "정차",
                trn_dptre_dt: "20260713060000",
                trn_arvl_dt: "20260713060000",
              }],
            },
            numOfRows: 10,
            pageNo: 1,
            totalCount: 1,
          },
        },
      }), { status: 200, headers: { "content-type": "application/json" } });
    },
  });

  assert.equal(requestedUrl.searchParams.get("serviceKey"), secret);
  assert.equal(requestedUrl.searchParams.get("cond[run_ymd::GTE]"), "20260713");
  assert.equal(requestedUrl.searchParams.get("cond[run_ymd::LTE]"), "20260713");
  assert.equal(evidence.providerResultCode, "0");
  assert.equal(evidence.rowCount, 1);
  assert.deepEqual(evidence.outputFields, KORAIL_TRAIN_OPERATION_APIS["korail-traveler-train-run-info"].expectedFields);
  assert.equal(evidence.credentialRedacted, true);
  assert.equal("rows" in evidence, false);
  assert.doesNotMatch(JSON.stringify(evidence), new RegExp(secret));
});

test("Korail 열차운행정보 probe는 provider 오류·빈 row·schema mismatch를 fail closed한다", async (context) => {
  const base = {
    sourceId: "korail-traveler-train-run-info",
    runDate: "20260713",
    serviceKey: "key",
  };

  await context.test("provider failure", async () => {
    await assert.rejects(probeKorailTrainOperationApi({
      ...base,
      fetchImpl: async () => new Response(JSON.stringify({
        response: { header: { resultCode: "30", resultMsg: "SERVICE KEY IS NOT REGISTERED" }, body: {} },
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /provider resultCode 30/);
  });

  await context.test("empty rows", async () => {
    await assert.rejects(probeKorailTrainOperationApi({
      ...base,
      fetchImpl: async () => new Response(JSON.stringify({
        response: {
          header: { resultCode: "0" },
          body: { items: { item: [] }, numOfRows: 10, pageNo: 1, totalCount: 0 },
        },
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /returned zero rows/);
  });

  await context.test("item field mismatch", async () => {
    await assert.rejects(probeKorailTrainOperationApi({
      ...base,
      fetchImpl: async () => new Response(JSON.stringify({
        response: {
          header: { resultCode: "0" },
          body: { items: { item: [{ run_ymd: "20260713" }] }, numOfRows: 10, pageNo: 1, totalCount: 1 },
        },
      }), { status: 200, headers: { "content-type": "application/json" } }),
    }), /item fields/);
  });
});
