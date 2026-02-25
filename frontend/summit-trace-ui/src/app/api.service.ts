import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';

export interface Site {
  siteId: string;
  siteCode: string;
  siteName: string;
  timezone: string;
}

@Injectable({ providedIn: 'root' })
export class ApiService {
  // In production behind nginx, we’ll proxy /api to the backend.
  private baseUrl = '';

  constructor(private http: HttpClient) {}

  health(): Observable<any> {
    return this.http.get(`/api/health`);
  }

  sites(): Observable<Site[]> {
    return this.http.get<Site[]>(`/api/master/sites`);
  }

  onHand(siteCode: string): Observable<any[]> {
    return this.http.get<any[]>(`/api/inventory/on-hand?siteCode=${encodeURIComponent(siteCode)}`);
  }
}